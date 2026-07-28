import SwiftUI

// the in-app breathing gate for websites. iOS chrome/brave can't run browser
// extensions, so the breathe moment lives here: one slow animated breath, then
// the site unblocks in every browser for its minutes. this is the one breathe
// surface that CAN animate (the shield is a static snapshot).
struct BreatheView: View {
    @EnvironmentObject var engine: RunEngine
    @EnvironmentObject var store: RunStore
    @Environment(\.dismiss) private var dismiss

    let platform: Platform

    @State private var start = Date()
    @State private var remaining: Int = 0

    private let tickTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var ready: Bool { remaining <= 0 }
    private var minutes: Int { store.webSessionMinutes(for: platform) }

    var body: some View {
        VStack(spacing: 0) {
            Text("RUNS")
                .font(Theme.mono(14, .bold))
                .tracking(3)
                .foregroundStyle(Theme.dim)
                .padding(.top, 28)

            Text(platform.name.uppercased())
                .font(Theme.mono(20, .bold))
                .tracking(2)
                .foregroundStyle(Theme.fg)
                .padding(.top, 10)

            Spacer()

            // one clock drives the orb and the caption, so nothing can drift
            // apart or land on a keyframe corner
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSince(start)
                let breath = Breath.amplitude(at: t)

                ZStack {
                    BreathOrb(breath: breath, trail: Breath.amplitude(at: t - Breath.trailLag))

                    // the centre belongs to the breath, then to the door
                    if ready {
                        door
                    } else {
                        caption(at: t, breath: breath)
                    }
                }
                .frame(height: 320)
                .animation(.easeInOut(duration: 0.55), value: ready)
            }

            Spacer()

            // the countdown gets out of the way instead of holding the centre
            Text(ready ? " " : "\(remaining)")
                .font(Theme.mono(15))
                .monospacedDigit()
                .foregroundStyle(Theme.dim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)

            Button {
                dismiss()
            } label: {
                Text("CLOSE")
                    .font(Theme.mono(13))
                    .foregroundStyle(Theme.dim)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 30)
                    .contentShape(Rectangle())
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .onAppear {
            start = Date()
            remaining = max(store.breatheSeconds, 1)
        }
        .onReceive(tickTimer) { _ in
            if remaining > 0 { remaining -= 1 }
        }
    }

    // no box: once the breath is served the words themselves are the door.
    // kerning, not tracking — tracking pads after the last glyph and would
    // knock the label off centre.
    private var door: some View {
        Button {
            engine.startWebSession(for: platform)
            dismiss()
        } label: {
            Text("OPEN \(minutes) MIN")
                .font(Theme.mono(22, .bold))
                .kerning(5)
                .foregroundStyle(Theme.fg)
                .padding(20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func caption(at t: TimeInterval, breath: Double) -> some View {
        ZStack {
            Text("breathe in").opacity(Breath.captionWeight(at: t))
            Text("breathe out").opacity(1 - Breath.captionWeight(at: t))
        }
        .font(Theme.mono(15))
        .kerning(2)
        .foregroundStyle(Theme.dim)
        .opacity(0.72 + 0.28 * breath)
    }
}

// light, not geometry. the body holds an even value out to ~0.6 of its radius
// and then feathers to nothing, so it reads as a lit sphere with no edge to
// see. behind it sits a wide atmosphere running a beat late, which is what
// gives the thing volume. no strokes anywhere.
private struct BreathOrb: View {
    let breath: Double
    let trail: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: Theme.fg.opacity(0.070), location: 0.30),
                            .init(color: Theme.fg.opacity(0.030), location: 0.62),
                            .init(color: Theme.fg.opacity(0.000), location: 1.00),
                        ],
                        center: .center, startRadius: 0, endRadius: 210
                    )
                )
                .frame(width: 420, height: 420)
                .scaleEffect(0.74 + 0.26 * trail)

            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: Theme.fg.opacity(0.20 + 0.10 * breath), location: 0.00),
                            .init(color: Theme.fg.opacity(0.17 + 0.09 * breath), location: 0.42),
                            .init(color: Theme.fg.opacity(0.13 + 0.07 * breath), location: 0.62),
                            .init(color: Theme.fg.opacity(0.05 + 0.03 * breath), location: 0.82),
                            .init(color: Theme.fg.opacity(0.00), location: 1.00),
                        ],
                        center: .center, startRadius: 0, endRadius: 132
                    )
                )
                .frame(width: 264, height: 264)
                .scaleEffect(0.60 + 0.40 * breath)
        }
        .frame(maxWidth: .infinity)
        // a wide flat gradient on near-black quantises into visible rings, and
        // scaling it makes those rings crawl. one still frame of grain over the
        // orb dithers them away.
        // its own square, sized past the atmosphere: laid over the 320pt row
        // instead, the field would be cut off and you'd see its edge
        .overlay(
            Grain()
                .frame(width: 500, height: 500)
                .mask(
                    RadialGradient(
                        stops: [
                            .init(color: .black, location: 0.00),
                            .init(color: .black, location: 0.44),
                            .init(color: .clear, location: 0.90),
                        ],
                        center: .center, startRadius: 0, endRadius: 250
                    )
                )
                .allowsHitTesting(false)
        )
    }
}

// generated once, tiled. deterministic so it never shimmers between frames.
private struct Grain: View {
    private static let tile: CGImage? = {
        let side = 96
        var bytes = [UInt8](repeating: 255, count: side * side * 4)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for i in stride(from: 0, to: bytes.count, by: 4) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let v = UInt8(truncatingIfNeeded: seed >> 40)
            bytes[i] = v
            bytes[i + 1] = v
            bytes[i + 2] = v
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }()

    var body: some View {
        if let tile = Self.tile {
            Image(decorative: tile, scale: 1)
                .resizable(resizingMode: .tile)
                .opacity(0.05)
        }
    }
}

// 4 in, hold, 6 out, rest — the long exhale is the part that actually settles
// you. every boundary is smoothstepped so the turn has no corner in it.
private enum Breath {
    static let inhale = 4.0
    static let hold = 1.0
    static let exhale = 6.0
    static let rest = 1.0
    static let cycle = inhale + hold + exhale + rest

    // the outer bloom lags the core by this much
    static let trailLag = 0.55

    // 0 = fully out, 1 = fully in
    static func amplitude(at t: TimeInterval) -> Double {
        let p = phase(t)
        if p < inhale { return smooth(p / inhale) }
        if p < inhale + hold { return 1 }
        if p < inhale + hold + exhale { return 1 - smooth((p - inhale - hold) / exhale) }
        return 0
    }

    // 1 = "breathe in", 0 = "breathe out". each crossfade lands just BEFORE its
    // turn, so the words are already right when the orb starts moving — and the
    // view opens on "breathe in" rather than fading into it.
    static func captionWeight(at t: TimeInterval) -> Double {
        let p = phase(t)
        let turn = inhale + hold
        let fade = 0.55
        if p < turn { return 1 }
        if p < turn + fade { return 1 - smooth((p - turn) / fade) }
        if p < cycle - fade { return 0 }
        return smooth((p - (cycle - fade)) / fade)
    }

    private static func phase(_ t: TimeInterval) -> Double {
        max(0, t).truncatingRemainder(dividingBy: cycle)
    }

    private static func smooth(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }
}
