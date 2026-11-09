import SwiftUI

/// Анимированный 4-полосный эквалайзер для отображения играющей музыки в вырезе и в плеере.
public struct EqualizerView: View {
    public let isPlaying: Bool
    public let color: Color
    public var barCount: Int = 4
    public var maxHeight: CGFloat = 14
    
    @State private var phase: Double = 0
    private let timer = Timer.publish(every: 0.16, on: .main, in: .common).autoconnect()
    
    public init(isPlaying: Bool, color: Color = .green, barCount: Int = 4, maxHeight: CGFloat = 14) {
        self.isPlaying = isPlaying
        self.color = color
        self.barCount = barCount
        self.maxHeight = maxHeight
    }
    
    public var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(color.gradient)
                    .frame(width: 2.8, height: barHeight(for: index))
                    .animation(.easeInOut(duration: 0.18), value: phase)
                    .animation(.easeInOut(duration: 0.25), value: isPlaying)
            }
        }
        .frame(height: maxHeight)
        .onReceive(timer) { _ in
            guard isPlaying else { return }
            phase += 0.65
        }
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        guard isPlaying else { return 3.5 }
        let wave = abs(sin(phase + Double(index) * 1.15))
        return max(3.5, CGFloat(wave) * maxHeight)
    }
}

/// Удобный модификатор подсветки кнопок при наведении курсора
public struct IslandHoverButtonStyle: ButtonStyle {
    @State private var isHovered = false
    public var cornerRadius: CGFloat = 10
    
    public init(cornerRadius: CGFloat = 10) {
        self.cornerRadius = cornerRadius
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : (isHovered ? 1.05 : 1.0))
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.18 : (isHovered ? 0.11 : 0.0)))
            )
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

