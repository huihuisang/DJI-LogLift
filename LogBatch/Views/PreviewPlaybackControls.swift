import SwiftUI

struct PreviewPlaybackControls: View {
    @Bindable var playback: PreviewPlayback

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if playback.isPlaying { playback.pause() } else { playback.play() }
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 22, height: 24)
            }
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityLabel(playback.isPlaying ? Text("Pause") : Text("Play"))
            .help(playback.isPlaying ? Text("Pause") : Text("Play"))
            .accessibilityIdentifier("preview-play-pause")
            .disabled(!playback.isReady)

            if let error = playback.error {
                Text("Playback unavailable").font(.system(size: 10)).lineLimit(1).help(error)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Slider(value: Binding(get: { playback.position }, set: { playback.seek(to: $0) }),
                       in: 0...max(0.001, playback.duration)) { Text("Playback position") } onEditingChanged: { editing in
                    if editing { playback.beginScrubbing() } else { playback.endScrubbing() }
                }
                .labelsHidden()
                .controlSize(.mini)
                .disabled(!playback.isReady)
                .accessibilityIdentifier("preview-timeline")
            }

            Text(verbatim: PreviewPlayback.timeLabel(playback.position) + " / " + PreviewPlayback.timeLabel(playback.duration))
                .font(.system(size: 10)).monospacedDigit().fixedSize()
                .accessibilityLabel(Text("Playback time"))

            Button {
                playback.isMuted.toggle()
            } label: {
                Image(systemName: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 22, height: 24)
            }
            .accessibilityLabel(playback.isMuted ? Text("Unmute") : Text("Mute"))
            .help(playback.isMuted ? Text("Unmute") : Text("Mute"))
            .accessibilityIdentifier("preview-mute")
            .disabled(!playback.isReady)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .tint(.white)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
    }
}
