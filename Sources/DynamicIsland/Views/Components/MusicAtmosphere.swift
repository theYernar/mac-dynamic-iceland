import SwiftUI
import CoreGraphics

struct MusicPalette: Equatable, Sendable {
    struct RGB: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double
        var color: Color { Color(red: red, green: green, blue: blue) }
    }

    let first: RGB
    let second: RGB
    var primary: Color { first.color }
    var secondary: Color { second.color }
    static let fallback = MusicPalette(first: RGB(red: 0.43, green: 0.53, blue: 0.98),
                                       second: RGB(red: 0.78, green: 0.38, blue: 0.65))

    // Цвет вычисляется один раз на обложку по маленькой CPU-копии, без фильтров в каждом кадре.
    static func extract(from image: CGImage) -> MusicPalette {
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard rendered else { return fallback }
        var weights = [Double](repeating: 0, count: 24)
        var reds = weights, greens = weights, blues = weights
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha > 0.5 else { continue }
            let r = min(1, Double(pixels[offset]) / (255 * alpha))
            let g = min(1, Double(pixels[offset + 1]) / (255 * alpha))
            let b = min(1, Double(pixels[offset + 2]) / (255 * alpha))
            let high = max(r, g, b), low = min(r, g, b), delta = high - low
            guard high > 0.08, delta > 0.035 else { continue }
            let saturation = delta / high
            guard saturation > 0.12 else { continue }
            let hue = hue(red: r, green: g, blue: b, high: high, delta: delta)
            let bucket = min(23, Int(hue * 24))
            let weight = saturation * saturation * sqrt(high) * alpha
            weights[bucket] += weight
            reds[bucket] += r * weight; greens[bucket] += g * weight; blues[bucket] += b * weight
        }
        let ranked = weights.indices.sorted { weights[$0] > weights[$1] }
        guard let best = ranked.first, weights[best] > 1.5 else { return fallback }
        func bucketHue(_ bucket: Int) -> Double {
            let r = reds[bucket] / weights[bucket], g = greens[bucket] / weights[bucket], b = blues[bucket] / weights[bucket]
            let high = max(r, g, b), delta = high - min(r, g, b)
            return hue(red: r, green: g, blue: b, high: high, delta: delta)
        }
        let mainHue = bucketHue(best)
        let alternate = ranked.dropFirst().first { bucket in
            let distance = abs(Double(bucket - best)) / 24
            return min(distance, 1 - distance) > 0.13 && weights[bucket] > weights[best] * 0.2
        }
        let otherHue = alternate.map(bucketHue) ?? (mainHue + 0.13).truncatingRemainder(dividingBy: 1)
        return MusicPalette(first: rgb(hue: mainHue, saturation: 0.62, brightness: 0.94),
                            second: rgb(hue: otherHue, saturation: 0.58, brightness: 0.85))
    }

    private static func hue(red: Double, green: Double, blue: Double, high: Double, delta: Double) -> Double {
        guard delta > 0 else { return 0 }
        let raw: Double
        if high == red { raw = (green - blue) / delta }
        else if high == green { raw = (blue - red) / delta + 2 }
        else { raw = (red - green) / delta + 4 }
        return (raw / 6 + 1).truncatingRemainder(dividingBy: 1)
    }

    private static func rgb(hue: Double, saturation: Double, brightness: Double) -> RGB {
        let sector = hue * 6, fraction = sector - floor(sector)
        let p = brightness * (1 - saturation), q = brightness * (1 - saturation * fraction)
        let t = brightness * (1 - saturation * (1 - fraction))
        switch Int(sector) % 6 {
        case 0: return RGB(red: brightness, green: t, blue: p)
        case 1: return RGB(red: q, green: brightness, blue: p)
        case 2: return RGB(red: p, green: brightness, blue: t)
        case 3: return RGB(red: p, green: q, blue: brightness)
        case 4: return RGB(red: t, green: p, blue: brightness)
        default: return RGB(red: brightness, green: p, blue: q)
        }
    }
}

private struct MusicPaletteKey: EnvironmentKey {
    static let defaultValue = MusicPalette.fallback
}

extension EnvironmentValues {
    var musicPalette: MusicPalette {
        get { self[MusicPaletteKey.self] }
        set { self[MusicPaletteKey.self] = newValue }
    }
}

struct MusicAtmosphere: View {
    let palette: MusicPalette
    let isPlaying: Bool
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var elapsed: TimeInterval = 0
    @State private var startedAt: Date?
    private var isMoving: Bool { isActive && isPlaying && !reduceMotion }

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 0.15, paused: !isMoving)) { context in
                let time = elapsed + (startedAt.map { max(0, context.date.timeIntervalSince($0)) } ?? 0)
                let phase = time / 16 * .pi * 2
                ZStack {
                    RadialGradient(colors: [palette.primary.opacity(0.3), palette.primary.opacity(0.075), .clear],
                                   center: UnitPoint(x: 0.16 + sin(phase) * 0.1, y: 0.5 + cos(phase * 0.7) * 0.13),
                                   startRadius: 0, endRadius: geometry.size.width * 0.72)
                    RadialGradient(colors: [palette.secondary.opacity(0.25), .clear],
                                   center: UnitPoint(x: 0.85 + cos(phase * 0.8) * 0.1, y: 0.78 + sin(phase) * 0.12),
                                   startRadius: 0, endRadius: geometry.size.width * 0.58)
                    RadialGradient(colors: [palette.primary.opacity(0.09), .clear],
                                   center: .bottom, startRadius: 0, endRadius: geometry.size.width * 0.45)
                    LinearGradient(colors: [.black.opacity(0.5), .clear, .black.opacity(0.18)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .animation(.linear(duration: 0.18), value: phase)
            }
        }
        .animation(.easeInOut(duration: 1.2), value: palette)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { updateClock(running: isMoving) }
        .onChange(of: isMoving) { _, moving in updateClock(running: moving) }
        .onDisappear { updateClock(running: false) }
    }

    private func updateClock(running: Bool) {
        if running {
            if startedAt == nil { startedAt = .now }
        } else if let start = startedAt {
            elapsed += max(0, Date().timeIntervalSince(start))
            startedAt = nil
        }
    }
}
