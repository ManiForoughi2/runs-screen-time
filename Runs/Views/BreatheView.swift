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

    @State private var inhale = false
    @State private var remaining: Int = 0

    private let phaseTimer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()
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

            ZStack {
                Circle()
                    .stroke(Theme.fg, lineWidth: 1.4)
                    .frame(width: 210, height: 210)
                    .scaleEffect(inhale ? 1.0 : 0.55)
                Circle()
                    .fill(Theme.fg.opacity(0.08))
                    .frame(width: 210, height: 210)
                    .scaleEffect(inhale ? 1.0 : 0.55)
            }
            .frame(height: 230)

            Text(inhale ? "breathe in…" : "breathe out…")
                .font(Theme.mono(15))
                .foregroundStyle(Theme.dim)
                .padding(.top, 26)
                .animation(nil, value: inhale)

            Spacer()

            Group {
                if ready {
                    Button {
                        engine.startWebSession(for: platform)
                        dismiss()
                    } label: {
                        Text("OPEN \(minutes) MIN")
                    }
                    .buttonStyle(OutlineButtonStyle(filled: true))
                } else {
                    Text("\(remaining)")
                        .font(Theme.mono(15))
                        .monospacedDigit()
                        .foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .padding(.horizontal, 40)

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
            remaining = max(store.breatheSeconds, 1)
            withAnimation(.easeInOut(duration: 4)) { inhale = true }
        }
        .onReceive(phaseTimer) { _ in
            withAnimation(.easeInOut(duration: 4)) { inhale.toggle() }
        }
        .onReceive(tickTimer) { _ in
            if remaining > 0 { remaining -= 1 }
        }
    }
}
