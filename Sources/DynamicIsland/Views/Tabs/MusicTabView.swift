import SwiftUI

public struct MusicTabView: View {
    @ObservedObject var musicManager: MusicManager
    @Binding var isSourcePickerPresented: Bool
    public let isVisible: Bool
    @Environment(\.musicPalette) private var palette

    @State private var isDraggingSlider = false
    @State private var dragTimeValue: Double = 0

    public init(musicManager: MusicManager, isSourcePickerPresented: Binding<Bool>, isVisible: Bool = true) {
        self.musicManager = musicManager
        self._isSourcePickerPresented = isSourcePickerPresented
        self.isVisible = isVisible
    }

    private var displayedTime: Double {
        isDraggingSlider ? dragTimeValue : musicManager.currentTime
    }

    public var body: some View {
        VStack(spacing: 12) {
            trackHeader
            timeline
            playbackControls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onChange(of: musicManager.selectedSessionId) { _, _ in isDraggingSlider = false }
        .onChange(of: musicManager.sessions.count) { _, count in
            if count < 2 { isSourcePickerPresented = false }
        }
    }

    // Обложка, название и исполнитель расположены одной строкой, как в системном плеере.
    private var trackHeader: some View {
        HStack(spacing: 12) {
            Button(action: musicManager.openActiveMusicApp) { artwork }
                .buttonStyle(MusicControlButtonStyle(tint: palette.primary))
                .help("Open \(musicManager.activeSource.displayName)")
                .accessibilityLabel("Open \(musicManager.activeSource.displayName)")

            VStack(alignment: .leading, spacing: 3) {
                Text(musicManager.trackTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .help(musicManager.trackTitle)
                Text(musicManager.playbackError ?? musicManager.trackArtist)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(musicManager.playbackError == nil ? Color.white.opacity(0.6) : Color.orange)
                    .lineLimit(1)
                    .help(musicManager.playbackError ?? musicManager.trackArtist)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if musicManager.sessions.count > 1 {
                Button {
                    isSourcePickerPresented.toggle()
                } label: {
                    equalizer
                }
                .buttonStyle(MusicControlButtonStyle(tint: palette.primary))
                .help("Playback Source")
                .accessibilityLabel("Playback Source")
                .popover(isPresented: $isSourcePickerPresented, arrowEdge: .bottom) { sourcePicker }
            } else {
                equalizer
            }
        }
        .frame(height: 58)
    }

    private var artwork: some View {
        ZStack {
            Color(white: 0.12)
            if let image = musicManager.artworkImage {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else if let icon = musicManager.appIconImage {
                Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit).padding(14)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.26), palette.primary.opacity(0.12), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 0.7
                )
        }
        .shadow(color: palette.primary.opacity(musicManager.isPlaying ? 0.24 : 0.1), radius: 9, x: 0, y: 3)
        .animation(.easeInOut(duration: 0.4), value: musicManager.isPlaying)
    }

    // Время находится по краям тонкой нейтральной полосы прогресса.
    private var timeline: some View {
        HStack(spacing: 10) {
            Text(formatSeconds(displayedTime)).frame(minWidth: 30, alignment: .leading)
            GeometryReader { geometry in
                let ratio = musicManager.duration > 0
                    ? min(max(displayedTime / musicManager.duration, 0), 1) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Rectangle().fill(
                        LinearGradient(colors: [palette.secondary.opacity(0.85), palette.primary, .white.opacity(0.9)], startPoint: .leading, endPoint: .trailing)
                    )
                        .frame(width: geometry.size.width * ratio)
                }
                .frame(height: 5)
                .clipShape(Capsule())
                .shadow(color: palette.primary.opacity(0.3), radius: 4, y: 1)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard musicManager.duration > 0, geometry.size.width > 0 else { return }
                            isDraggingSlider = true
                            dragTimeValue = min(max(value.location.x / geometry.size.width, 0), 1) * musicManager.duration
                        }
                        .onEnded { value in
                            defer { isDraggingSlider = false }
                            guard musicManager.duration > 0, geometry.size.width > 0 else { return }
                            let target = min(max(value.location.x / geometry.size.width, 0), 1) * musicManager.duration
                            musicManager.seek(to: target)
                        }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Playback position")
                .accessibilityValue(formatSeconds(displayedTime))
                .accessibilityAdjustableAction { direction in
                    guard musicManager.duration > 0 else { return }
                    let delta: Double = direction == .increment ? 5 : -5
                    musicManager.seek(to: min(max(musicManager.currentTime + delta, 0), musicManager.duration))
                }
            }
            Text(musicManager.duration > 0
                ? "−\(formatSeconds(max(0, musicManager.duration - displayedTime)))" : "LIVE")
                .frame(minWidth: 36, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(.white.opacity(0.6))
        .frame(height: 18)
    }

    private var equalizer: some View {
        EqualizerView(isPlaying: musicManager.isPlaying, color: palette.primary.opacity(0.85), barCount: 5, maxHeight: 16, isActive: isVisible)
            .frame(width: 24, height: 26)
            .contentShape(Rectangle())
            .accessibilityHidden(true)
    }

    private var playbackControls: some View {
        HStack(spacing: 24) {
            transportButton("backward.fill", label: "Previous Track", size: 17, action: musicManager.previousTrack)
            transportButton(musicManager.isPlaying ? "pause.fill" : "play.fill",
                            label: musicManager.isPlaying ? "Pause" : "Play",
                            size: 21, action: musicManager.togglePlayPause)
            transportButton("forward.fill", label: "Next Track", size: 17, action: musicManager.nextTrack)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 34)
    }

    private func transportButton(_ symbol: String, label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(0.98))
                .shadow(color: palette.primary.opacity(size > 17 && musicManager.isPlaying ? 0.35 : 0), radius: 7)
                .animation(.easeInOut(duration: 0.3), value: musicManager.isPlaying)
                .frame(width: 32, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(MusicControlButtonStyle(tint: palette.primary))
        .help(label)
        .accessibilityLabel(label)
        .disabled(musicManager.selectedSessionId == nil)
    }

    // Выбор приложения доступен через эквалайзер, только когда источников несколько.
    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Playback Source")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            if musicManager.sessions.isEmpty {
                Text("Play audio in an app to choose a source.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(musicManager.sessions) { session in
                            Button {
                                musicManager.selectSession(id: session.id)
                            } label: {
                                HStack(spacing: 9) {
                                    if let icon = session.appIconImage {
                                        Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                                    } else {
                                        Image(systemName: session.source.iconName).frame(width: 18)
                                    }
                                    Text(session.source.displayName).lineLimit(1)
                                    Spacer(minLength: 6)
                                    if musicManager.selectedSessionId == session.id {
                                        Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                                    }
                                }
                                .font(.system(size: 12))
                                .padding(.horizontal, 8)
                                .frame(height: 31)
                                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(musicManager.selectedSessionId == session.id ? 0.1 : 0)))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: min(CGFloat(musicManager.sessions.count) * 34, 136))
            }
        }
        .padding(16)
        .frame(width: 250)
        .preferredColorScheme(.dark)
    }

    private func formatSeconds(_ value: Double) -> String {
        guard value.isFinite, value >= 0, value < Double(Int.max) else { return "0:00" }
        let seconds = Int(value)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct MusicControlButtonStyle: ButtonStyle {
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(isEnabled ? (configuration.isPressed ? 0.19 : (isHovered ? 0.1 : 0)) : 0))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(isEnabled && isHovered ? 0.08 : 0), lineWidth: 0.5)
            }
            .scaleEffect(reduceMotion || !isEnabled ? 1 : (configuration.isPressed ? 0.93 : (isHovered ? 1.055 : 1)))
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.easeOut(duration: 0.16), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}
