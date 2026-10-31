@preconcurrency import AVFoundation
import Foundation
import LogBatchCore
import Observation

private struct PlaybackFrame: @unchecked Sendable {
    let buffer: CVPixelBuffer
}

@MainActor @Observable
final class PreviewPlayback {
    private(set) var frames: PreviewImages?
    private(set) var sourceURL: URL?
    private(set) var position = 0.0
    private(set) var duration = 0.0
    private(set) var displayedTime = 0.0
    private(set) var isReady = false
    private(set) var isPlaying = false
    private(set) var error: String?
    var isMuted = false { didSet { player.isMuted = isMuted } }

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var output: AVPlayerItemVideoOutput?
    @ObservationIgnored private var renderer: VideoPreviewRenderer?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObservation: NSObjectProtocol?
    @ObservationIgnored private var renderTask: Task<PreviewImages, Error>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var frameGeneration = 0
    @ObservationIgnored private var seekPending = false
    @ObservationIgnored private var needsFrame = false
    @ObservationIgnored private var frameDeadline = Date.distantPast
    @ObservationIgnored private var isScrubbing = false
    @ObservationIgnored private var resumesAfterScrubbing = false

    isolated deinit {
        ticker?.invalidate()
        player.pause()
        renderTask?.cancel()
        if let endObservation { NotificationCenter.default.removeObserver(endObservation) }
    }

    func prepare(source: URL, cube: CubeLUT, poster: PreviewImages, startAt: Double = 0) async throws {
        stop()
        let token = generation
        let asset = AVURLAsset(url: source)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first, tracks.count == 1 else { throw LogBatchError.unsupportedMedia }
        let transform = try await track.load(.preferredTransform)
        let seconds = try await asset.load(.duration).seconds
        guard seconds.isFinite, seconds > 0 else { throw LogBatchError.unsupportedMedia }
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }

        frames = poster
        sourceURL = source
        duration = seconds
        renderer = VideoPreviewRenderer(cube: cube, transform: transform)
        let item = AVPlayerItem(asset: asset)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: ColorPipeline.readerSettings)
        output.suppressesPlayerRendering = true
        item.add(output)
        self.output = output
        player.automaticallyWaitsToMinimizeStalling = false
        player.isMuted = isMuted
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
            Task { @MainActor in
                guard let self, let item, self.generation == token else { return }
                switch item.status {
                case .readyToPlay:
                    self.isReady = true
                    if startAt > 0 { self.seek(to: startAt) }
                case .failed:
                    self.error = item.error?.localizedDescription ?? String(localized: "Video playback failed.")
                    self.invalidateFrame()
                    self.needsFrame = false
                    self.seekPending = false
                    self.pause()
                    self.stopTicker()
                    self.isReady = false
                default: break
                }
            }
        }
        endObservation = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                               object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.generation == token else { return }
                self.player.pause()
                self.isPlaying = false
                self.position = self.duration
                self.needsFrame = false
                self.stopTicker()
            }
        }
        player.replaceCurrentItem(with: item)
    }

    func play() {
        guard isReady, error == nil else { return }
        isPlaying = true
        if position >= duration - 0.04 {
            seek(to: 0)
        } else if !seekPending {
            player.play()
        }
        startTicker()
    }

    func pause() {
        player.pause()
        isPlaying = false
        resumesAfterScrubbing = false
        if !seekPending, !isScrubbing {
            let seconds = player.currentTime().seconds
            if seconds.isFinite { position = min(duration, max(0, seconds)) }
        }
        if !needsFrame { stopTicker() }
    }

    func seek(to seconds: Double) {
        guard isReady, seconds.isFinite else { return }
        invalidateFrame()
        let token = generation
        let request = frameGeneration
        position = min(duration, max(0, seconds))
        seekPending = true
        needsFrame = true
        frameDeadline = Date().addingTimeInterval(3)
        player.pause()
        let time = CMTime(seconds: min(position, max(0, duration - 0.001)), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard let self, self.generation == token, self.frameGeneration == request else { return }
                self.seekPending = false
                if finished {
                    if self.isPlaying { self.player.play() }
                    self.startTicker()
                } else {
                    self.needsFrame = false
                    self.pause()
                }
            }
        }
        startTicker()
    }

    func beginScrubbing() {
        let wasPlaying = isPlaying
        pause()
        isScrubbing = true
        resumesAfterScrubbing = wasPlaying
    }

    func endScrubbing() {
        isScrubbing = false
        let resume = resumesAfterScrubbing
        resumesAfterScrubbing = false
        if resume, position < duration - 0.04 { play() }
    }

    func stop() {
        generation = UUID()
        invalidateFrame()
        stopTicker()
        player.pause()
        statusObservation = nil
        if let endObservation { NotificationCenter.default.removeObserver(endObservation) }
        endObservation = nil
        player.replaceCurrentItem(with: nil)
        output = nil
        renderer = nil
        frames = nil
        sourceURL = nil
        position = 0
        duration = 0
        displayedTime = 0
        isReady = false
        isPlaying = false
        error = nil
        seekPending = false
        needsFrame = false
        isScrubbing = false
        resumesAfterScrubbing = false
    }

    static func timeLabel(_ seconds: Double) -> String {
        let value = seconds.isFinite ? Int(max(0, seconds)) : 0
        if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) }
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    private func invalidateFrame() {
        frameGeneration += 1
        renderTask?.cancel()
    }

    private func startTicker() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard isReady else { return }
        let time = player.currentTime()
        if isPlaying, !seekPending, !isScrubbing, time.seconds.isFinite {
            position = min(duration, max(0, time.seconds))
        }
        if !seekPending, renderTask == nil, let output, let renderer,
           output.hasNewPixelBuffer(forItemTime: time) {
            var displayTime = CMTime.invalid
            if let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: &displayTime) {
                let frame = PlaybackFrame(buffer: buffer)
                let token = generation
                let request = frameGeneration
                let seconds = displayTime.isValid ? displayTime.seconds : time.seconds
                needsFrame = false
                let task = Task.detached(priority: .userInitiated) {
                    try Task.checkCancellation()
                    let images = try renderer.render(frame.buffer)
                    try Task.checkCancellation()
                    return images
                }
                renderTask = task
                Task { [weak self] in
                    let result = await task.result
                    guard let self else { return }
                    self.renderTask = nil
                    guard self.generation == token, self.frameGeneration == request else { return }
                    switch result {
                    case .success(let images):
                        self.frames = images
                        if seconds.isFinite { self.displayedTime = max(0, seconds) }
                    case .failure(let error):
                        if !(error is CancellationError) {
                            self.error = error.localizedDescription
                            self.pause()
                        }
                    }
                    if !self.isPlaying, !self.needsFrame { self.stopTicker() }
                }
            }
        }
        if !isPlaying, renderTask == nil, (!needsFrame || Date() >= frameDeadline) { stopTicker() }
    }
}
