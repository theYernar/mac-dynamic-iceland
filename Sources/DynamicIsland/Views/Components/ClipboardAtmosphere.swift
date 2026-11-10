import SwiftUI

/// Ненавязчивое свечение, которое работает только пока виден буфер обмена.
public struct ClipboardAtmosphere: View {
    public let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var elapsed: TimeInterval = 0
    @State private var motionStartedAt: Date?

    public init(isActive: Bool) {
        self.isActive = isActive
    }

    private var motionEnabled: Bool {
        isActive && !reduceMotion
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: !motionEnabled || motionStartedAt == nil)) { timeline in
            GeometryReader { geometry in
                let time = elapsed + (motionStartedAt.map { max(0, timeline.date.timeIntervalSince($0)) } ?? 0)
                let phase = time * (.pi * 2 / 100)
                let radius = max(geometry.size.width * 0.72, 180)

                ZStack {
                    Color(red: 0.025, green: 0.032, blue: 0.065)

                    RadialGradient(
                        colors: [Color.indigo.opacity(0.24), Color.indigo.opacity(0.07), .clear],
                        center: UnitPoint(x: 0.12 + sin(phase) * 0.045, y: 0.02 + cos(phase) * 0.04),
                        startRadius: 0,
                        endRadius: radius
                    )

                    RadialGradient(
                        colors: [Color.purple.opacity(0.16), .clear],
                        center: UnitPoint(x: 0.9 + cos(phase * 0.8) * 0.035, y: 0.12 + sin(phase * 0.8) * 0.05),
                        startRadius: 0,
                        endRadius: radius * 0.82
                    )

                    RadialGradient(
                        colors: [Color.cyan.opacity(0.1), .clear],
                        center: UnitPoint(x: 0.54 + sin(phase * 0.7) * 0.055, y: 1.02 + cos(phase * 0.7) * 0.035),
                        startRadius: 0,
                        endRadius: radius * 0.74
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            updateMotion(enabled: motionEnabled)
        }
        .onChange(of: motionEnabled) { _, enabled in
            updateMotion(enabled: enabled)
        }
        .onDisappear {
            updateMotion(enabled: false)
        }
    }

    private func updateMotion(enabled: Bool) {
        if enabled {
            if motionStartedAt == nil { motionStartedAt = Date() }
        } else if let startedAt = motionStartedAt {
            elapsed += max(0, Date().timeIntervalSince(startedAt))
            motionStartedAt = nil
        }
    }
}
