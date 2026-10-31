@preconcurrency import AVFoundation
import Foundation
import LogBatchCore
import XCTest

final class PreviewPlaybackTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testPrepareIsPausedAndPlaybackAdvancesActualFrames() async throws {
        let playback = try await makePlayback()
        defer { playback.stop() }
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.position, 0, accuracy: 0.05)
        XCTAssertEqual(playback.duration, 1, accuracy: 0.05)

        playback.play()
        try await waitUntil { playback.displayedTime > 0.15 }
        playback.pause()
        let pausedPosition = playback.position
        XCTAssertGreaterThan(pausedPosition, 0.1)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.position, pausedPosition, accuracy: 0.05)
    }

    @MainActor
    func testPausedSeekUpdatesFrameWithoutStartingPlayback() async throws {
        let playback = try await makePlayback()
        defer { playback.stop() }
        playback.seek(to: 0.65)
        try await waitUntil { abs(playback.displayedTime - 0.65) < 0.08 }
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.position, 0.65, accuracy: 0.05)
    }

    @MainActor
    func testPlaybackEndCanRestartFromBeginning() async throws {
        let playback = try await makePlayback()
        defer { playback.stop() }
        playback.seek(to: 0.85)
        try await waitUntil { playback.displayedTime > 0.8 }
        playback.play()
        try await waitUntil { !playback.isPlaying && playback.position > 0.95 }
        playback.play()
        try await waitUntil { playback.isPlaying && playback.displayedTime < 0.5 }
    }

    @MainActor
    func testStopDuringSeekDiscardsPendingFramesAndReleasesSource() async throws {
        let playback = try await makePlayback()
        playback.play()
        playback.seek(to: 0.7)
        playback.stop()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(playback.frames)
        XCTAssertNil(playback.sourceURL)
        XCTAssertFalse(playback.isReady)
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.position, 0)
    }

    @MainActor
    func testLatestPausedSeekWins() async throws {
        let playback = try await makePlayback()
        defer { playback.stop() }
        playback.seek(to: 0.8)
        playback.seek(to: 0.2)
        playback.seek(to: 0.6)
        try await waitUntil { abs(playback.displayedTime - 0.6) < 0.08 }
        XCTAssertEqual(playback.position, 0.6, accuracy: 0.05)
        XCTAssertFalse(playback.isPlaying)
    }

    @MainActor
    func testDecodedPlaybackFramesMatchSystemOrientationAndIdentityLUT() async throws {
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["LOGBATCH_FIXTURE_DIR"])
        for rotation in [0, 90, 180, 270] {
            for mirrored in [false, true] {
                let name = "synthetic-orientation-\(rotation)-\(mirrored).mp4"
                let source = URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent(name)
                let playback = try await makePlayback(source: source)
                playback.seek(to: 0.5)
                try await waitUntil { abs(playback.displayedTime - 0.5) < 0.08 }
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: source))
                generator.appliesPreferredTrackTransform = true
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = .zero
                let time = CMTime(seconds: playback.displayedTime, preferredTimescale: 600)
                let reference = try await generator.image(at: time).image
                let frames = try XCTUnwrap(playback.frames)
                for image in [frames.original, frames.converted] {
                    XCTAssertEqual(image.width, reference.width, name)
                    XCTAssertEqual(image.height, reference.height, name)
                    XCTAssertLessThan(PreviewOrientationTests.pixelError(image, reference), 8, name)
                }
                playback.stop()
            }
        }
    }

    @MainActor
    func testScrubbingResumesOnlyPreviouslyPlayingVideo() async throws {
        let playback = try await makePlayback()
        defer { playback.stop() }
        playback.play()
        try await waitUntil { playback.displayedTime > 0.1 }
        playback.beginScrubbing()
        XCTAssertFalse(playback.isPlaying)
        playback.seek(to: 0.5)
        playback.endScrubbing()
        try await waitUntil { playback.isPlaying && playback.displayedTime > 0.55 }

        playback.pause()
        playback.beginScrubbing()
        playback.seek(to: 0.25)
        playback.endScrubbing()
        try await waitUntil { abs(playback.displayedTime - 0.25) < 0.08 }
        XCTAssertFalse(playback.isPlaying)
    }

    @MainActor
    func testScrubbingToEndDoesNotRestartAutomatically() async throws {
        let playback = try await makePlayback()
        defer { playback.stop() }
        playback.play()
        try await waitUntil { playback.displayedTime > 0.1 }
        playback.beginScrubbing()
        playback.seek(to: playback.duration)
        playback.endScrubbing()
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.position, playback.duration, accuracy: 0.05)
        try await waitUntil { playback.displayedTime > 0.9 }
    }

    @MainActor
    func testSwitchingSourceDiscardsOldPlaybackAndStartsPaused() async throws {
        let playback = try await makePlayback()
        defer { playback.stop() }
        playback.play()
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["LOGBATCH_FIXTURE_DIR"])
        let source = URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent("synthetic-rotated.mp4")
        let cube = try identityCube()
        let poster = try await VideoPreview.load(source: source, cube: cube)
        try await playback.prepare(source: source, cube: cube, poster: poster)
        try await waitUntil { playback.isReady }
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.sourceURL, source)
        XCTAssertEqual(playback.position, 0)
        XCTAssertEqual(playback.frames?.original.width, 180)
        XCTAssertEqual(playback.frames?.original.height, 320)
    }

    @MainActor
    func testMissingMediaDoesNotLeaveThePreviousPlayerActive() async throws {
        let playback = try await makePlayback()
        defer { playback.stop() }
        playback.play()
        let poster = try XCTUnwrap(playback.frames)
        do {
            try await playback.prepare(source: URL(fileURLWithPath: "/missing-\(UUID().uuidString).mp4"),
                                       cube: identityCube(), poster: poster)
            XCTFail("Missing media must fail preparation")
        } catch {
            XCTAssertFalse(playback.isPlaying)
            XCTAssertFalse(playback.isReady)
            XCTAssertNil(playback.sourceURL)
            XCTAssertNil(playback.frames)
        }
    }

    @MainActor
    func testPlayingControllerCanBeReleasedWithoutRetainingItsTimer() async throws {
        var playback: PreviewPlayback? = try await makePlayback()
        weak var releasedPlayback = playback
        playback?.play()
        playback = nil
        try await waitUntil { releasedPlayback == nil }
    }

    @MainActor
    func testBatchReloadPreservesPositionAndClearReleasesPlayback() async throws {
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["LOGBATCH_FIXTURE_DIR"])
        let source = URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent("synthetic.mp4")
        let store = BatchStore()
        defer { store.playback.stop() }
        store.items = [BatchItem(url: source)]
        store.selectedItemID = store.items[0].id
        store.playback.isMuted = true
        await store.loadPreview()
        try await waitUntil { store.playback.isReady }
        store.playback.seek(to: 0.5)
        try await waitUntil { abs(store.playback.displayedTime - 0.5) < 0.08 }

        await store.loadPreview()
        try await waitUntil { store.playback.isReady && abs(store.playback.displayedTime - 0.5) < 0.08 }
        XCTAssertFalse(store.playback.isPlaying)
        store.clear()
        XCTAssertNil(store.preview)
        XCTAssertNil(store.playback.frames)
        XCTAssertNil(store.playback.sourceURL)
        XCTAssertFalse(store.playback.isReady)
    }

    @MainActor
    private func makePlayback(source requestedSource: URL? = nil) async throws -> PreviewPlayback {
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["LOGBATCH_FIXTURE_DIR"])
        let source = requestedSource ?? URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent("synthetic.mp4")
        let cube = try identityCube()
        let poster = try await VideoPreview.load(source: source, cube: cube)
        let playback = PreviewPlayback()
        playback.isMuted = true
        try await playback.prepare(source: source, cube: cube, poster: poster)
        try await waitUntil { playback.isReady }
        return playback
    }

    private func identityCube() throws -> CubeLUT {
        try CubeLUT(data: Data("LUT_3D_SIZE 2\n0 0 0\n1 0 0\n0 1 0\n1 1 0\n0 0 1\n1 0 1\n0 1 1\n1 1 1\n".utf8))
    }

    @MainActor
    private func waitUntil(_ predicate: () -> Bool, timeout: TimeInterval = 4) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(predicate(), "Playback did not reach the expected state")
        if !predicate() { throw NSError(domain: "PreviewPlaybackTests", code: 1) }
    }
}
