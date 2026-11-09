import SwiftUI

public struct MusicTabView: View {
    @ObservedObject var musicManager: MusicManager
    @ObservedObject var audioManager: AudioControlManager
    
    @State private var isDraggingSlider: Bool = false
    @State private var dragTimeValue: Double = 0
    
    public init(musicManager: MusicManager, audioManager: AudioControlManager) {
        self.musicManager = musicManager
        self.audioManager = audioManager
    }
    
    public var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Обложка альбома / видео с мягким свечением и иконкой приложения
            Button(action: { musicManager.openActiveMusicApp() }) {
                ZStack(alignment: .bottomTrailing) {
                    if let nsImage = musicManager.artworkImage {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 84, height: 84)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: musicManager.activeSource.accentColor.opacity(0.35), radius: 8, x: 0, y: 3)
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        musicManager.activeSource.accentColor.opacity(0.85),
                                        Color.purple.opacity(0.6),
                                        Color(white: 0.12)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 84, height: 84)
                            .overlay(
                                Group {
                                    if let appIcon = musicManager.appIconImage {
                                        Image(nsImage: appIcon)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 40, height: 40)
                                            .shadow(color: .black.opacity(0.4), radius: 4)
                                    } else {
                                        Image(systemName: musicManager.isPlaying ? "waveform" : "music.quarternote.3")
                                            .font(.system(size: 30, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.9))
                                    }
                                }
                            )
                    }
                    
                    // Мини-бейдж активного приложения (Firefox / Chrome / Safari / Spotify / Apple Music)
                    Group {
                        if let appIcon = musicManager.appIconImage {
                            Image(nsImage: appIcon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(Color.black.opacity(0.75)))
                        } else {
                            Image(systemName: musicManager.activeSource.iconName)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(Circle().fill(musicManager.activeSource.accentColor))
                        }
                    }
                    .offset(x: 4, y: 4)
                }
                .frame(width: 88, height: 88)
            }
            .buttonStyle(.plain)
            .help("Open \(musicManager.activeSource.displayName)")
            
            // Правая часть: Инфо о треке/видео + переключатель источников + таймлайн + кнопки
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(musicManager.trackTitle)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        
                        Text(musicManager.playbackError ?? musicManager.trackArtist)
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundStyle(musicManager.playbackError == nil ? Color.white.opacity(0.62) : Color.orange)
                            .lineLimit(1)
                            .help(musicManager.playbackError ?? musicManager.trackArtist)
                    }
                    
                    Spacer(minLength: 4)
                    
                    // Переключатель доступных аудио-источников (например, Firefox ⇄ Spotify) + эквалайзер
                    HStack(spacing: 5) {
                        if musicManager.sessions.count > 1 {
                            ForEach(musicManager.sessions) { session in
                                sourcePickerButton(for: session)
                            }
                        } else {
                            Text(musicManager.activeSource.displayName)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(musicManager.activeSource.accentColor)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(
                                    Capsule()
                                        .fill(musicManager.activeSource.accentColor.opacity(0.16))
                                )
                        }
                        
                        EqualizerView(
                            isPlaying: musicManager.isPlaying,
                            color: musicManager.activeSource.accentColor,
                            barCount: 4,
                            maxHeight: 14
                        )
                    }
                }
                
                // Интерактивная полоса прогресса
                VStack(spacing: 3) {
                    GeometryReader { geo in
                        let total = max(musicManager.duration, 1)
                        let current = isDraggingSlider ? dragTimeValue : musicManager.currentTime
                        let ratio = musicManager.duration > 0 ? min(max(current / total, 0), 1) : 0
                        
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.14))
                                .frame(height: 5)
                            
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.white, musicManager.activeSource.accentColor],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(6, geo.size.width * ratio), height: 5)
                        }
                        .frame(height: 11)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard musicManager.duration > 0 else { return }
                                    isDraggingSlider = true
                                    let frac = min(max(value.location.x / geo.size.width, 0), 1)
                                    dragTimeValue = frac * musicManager.duration
                                }
                                .onEnded { value in
                                    guard musicManager.duration > 0 else { return }
                                    let frac = min(max(value.location.x / geo.size.width, 0), 1)
                                    let target = frac * musicManager.duration
                                    musicManager.seek(to: target)
                                    isDraggingSlider = false
                                }
                        )
                    }
                    .frame(height: 11)
                    
                    HStack {
                        Text(formatSeconds(isDraggingSlider ? dragTimeValue : musicManager.currentTime))
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.48))
                        Spacer()
                        Text(musicManager.duration > 0 ? "-\(formatSeconds(max(0, musicManager.duration - (isDraggingSlider ? dragTimeValue : musicManager.currentTime))))" : "LIVE")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.48))
                    }
                }
                
                // Кнопки управления воспроизведением и громкостью
                HStack(spacing: 12) {
                    Button(action: { musicManager.previousTrack() }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 28, height: 26)
                    }
                    .buttonStyle(IslandHoverButtonStyle(cornerRadius: 8))
                    
                    Button(action: { musicManager.togglePlayPause() }) {
                        Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 34, height: 28)
                            .background(
                                Capsule()
                                    .fill(Color.white)
                                    .shadow(color: .white.opacity(0.25), radius: 5)
                            )
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { musicManager.nextTrack() }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 28, height: 26)
                    }
                    .buttonStyle(IslandHoverButtonStyle(cornerRadius: 8))
                    
                    Spacer()
                    
                    // Быстрый регулятор громкости прямо в плеере
                    HStack(spacing: 6) {
                        Button(action: { audioManager.toggleMute() }) {
                            Image(systemName: volumeIcon)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.75))
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                        
                        GeometryReader { geo in
                            let volRatio = audioManager.isMuted ? 0.0 : audioManager.volume
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.14))
                                    .frame(height: 4)
                                Capsule()
                                    .fill(Color.white.opacity(0.85))
                                    .frame(width: max(4, geo.size.width * volRatio), height: 4)
                            }
                            .frame(height: 14)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { val in
                                        let ratio = min(max(val.location.x / geo.size.width, 0), 1)
                                        audioManager.setSystemVolume(ratio)
                                    }
                            )
                        }
                        .frame(width: 76, height: 14)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    
    // MARK: - Кнопка выбора источника (Firefox / Spotify / Apple Music / Chrome)
    
    private func sourcePickerButton(for session: MediaSession) -> some View {
        let isSelected = (musicManager.selectedSessionId == session.id)
        return Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                musicManager.selectSession(id: session.id)
            }
        }) {
            HStack(spacing: 4) {
                if let icon = session.appIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: session.source.iconName)
                        .font(.system(size: 9, weight: .bold))
                }
                
                Text(session.source.displayName)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                
                if session.isPlaying {
                    Circle()
                        .fill(session.source.accentColor)
                        .frame(width: 5, height: 5)
                }
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(
                        isSelected
                            ? session.source.accentColor.opacity(0.28)
                            : Color.white.opacity(0.07)
                    )
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? session.source.accentColor.opacity(0.85) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .help("Control \(session.source.displayName): \(session.title)")
    }
    
    private var volumeIcon: String {
        if audioManager.isMuted || audioManager.volume == 0 {
            return "speaker.slash.fill"
        } else if audioManager.volume < 0.35 {
            return "speaker.wave.1.fill"
        } else if audioManager.volume < 0.7 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
    
    private func formatSeconds(_ value: Double) -> String {
        guard value.isFinite && value >= 0 else { return "00:00" }
        let total = Int(value)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
