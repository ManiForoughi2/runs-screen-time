import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var store: RunStore
    var onFinish: () -> Void

    @State private var page = 0

    private enum Slide {
        case card(OnboardCard)
        case modeChooser
        case poolSize
    }

    private let intro: [OnboardCard] = [
        OnboardCard(
            kicker: "THE IDEA",
            title: "you don't get\nendless scrolling.",
            body: "you get a few short runs a day. that's it."
        ),
        OnboardCard(
            kicker: "A RUN",
            title: "tap an app.\nthe clock starts.",
            body: "App opens for 3 minutes. a timer counts down on your lock screen the whole time."
        ),
        OnboardCard(
            kicker: "WHEN IT ENDS",
            title: "the app locks\nback up.",
            body: "out of runs for the day? it stays locked until tomorrow."
        ),
        OnboardCard(
            kicker: "YOUR CALL",
            title: "you set the\nnumbers.",
            body: "minutes per app are yours. first, how should runs work?"
        )
    ]

    private let outro = OnboardCard(
        kicker: "TWO STEPS LEFT",
        title: "allow screen time,\nthen pick your apps.",
        body: "screen time is how screenrun locks an app when the clock runs out. nothing leaves your phone."
    )

    // the pool-size slide only appears once shared mode is picked
    private var slides: [Slide] {
        var s = intro.map { Slide.card($0) }
        s.append(.modeChooser)
        if store.runMode == .shared { s.append(.poolSize) }
        s.append(.card(outro))
        return s
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    finish()
                } label: {
                    Text("SKIP")
                        .font(Theme.mono(12, .semibold))
                        .foregroundStyle(Theme.dim)
                        .padding(.vertical, 8)
                        .padding(.leading, 16)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            TabView(selection: $page) {
                ForEach(slides.indices, id: \.self) { i in
                    slideView(slides[i]).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: page)
            .animation(.easeInOut, value: slides.count)
            .onChange(of: slides.count) { newCount in
                if page > newCount - 1 { page = newCount - 1 }
            }

            HStack(spacing: 8) {
                ForEach(slides.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Theme.fg : Theme.faint)
                        .frame(width: i == page ? 22 : 7, height: 7)
                        .animation(.easeInOut(duration: 0.2), value: page)
                }
            }
            .padding(.bottom, 28)

            Button {
                if page < slides.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    finish()
                }
            } label: {
                Text(page < slides.count - 1 ? "NEXT" : "LET'S GO")
            }
            .buttonStyle(OutlineButtonStyle(filled: page == slides.count - 1))
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
        }
        .screenBackground()
    }

    @ViewBuilder
    private func slideView(_ slide: Slide) -> some View {
        switch slide {
        case .card(let c): CardView(card: c)
        case .modeChooser: RunModeChooser(store: store)
        case .poolSize: PoolSizeChooser(store: store)
        }
    }

    private func finish() {
        store.setOnboarded(true)
        onFinish()
    }
}

private struct OnboardCard {
    let kicker: String
    let title: String
    let body: String
}

private struct RunModeChooser: View {
    @ObservedObject var store: RunStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text("HOW RUNS WORK")
                .font(Theme.mono(12, .bold))
                .tracking(3)
                .foregroundStyle(Theme.dim)
            Text("one pool, or\nper app?")
                .font(Theme.mono(30, .bold))
                .foregroundStyle(Theme.fg)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                option(
                    title: "SHARED POOL",
                    detail: "one pile of runs, spend it on any app.",
                    selected: store.runMode == .shared
                ) { store.setRunMode(.shared, sharedPool: store.sharedRuns) }

                option(
                    title: "RUNS PER APP",
                    detail: "each app gets its own runs per day.",
                    selected: store.runMode == .perApp
                ) { store.setRunMode(.perApp) }
            }
            .padding(.top, 6)

            Text("change this any time in settings.")
                .font(Theme.mono(12))
                .foregroundStyle(Theme.dim)
                .padding(.top, 2)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
    }

    private func option(title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Circle()
                    .strokeBorder(Theme.fg, lineWidth: 1.4)
                    .background(Circle().fill(selected ? Theme.fg : Color.clear))
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Theme.mono(16, .bold)).foregroundStyle(Theme.fg)
                    Text(detail).font(Theme.mono(12)).foregroundStyle(Theme.dim)
                }
                Spacer()
            }
            .padding(16)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? Theme.fg : Theme.hairline, lineWidth: selected ? 1.6 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

private struct PoolSizeChooser: View {
    @ObservedObject var store: RunStore

    private var count: Int { store.sharedRuns }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text("SHARED POOL")
                .font(Theme.mono(12, .bold))
                .tracking(3)
                .foregroundStyle(Theme.dim)
            Text("how many runs\na day?")
                .font(Theme.mono(30, .bold))
                .foregroundStyle(Theme.fg)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 20) {
                stepButton("–") { set(count - 1) }
                Text("\(count)")
                    .font(Theme.mono(56, .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.fg)
                    .frame(minWidth: 90)
                    .contentTransition(.numericText())
                stepButton("+") { set(count + 1) }
                Spacer()
            }
            .padding(.top, 8)

            Text("\(count) runs total, split across all your apps.")
                .font(Theme.mono(12))
                .foregroundStyle(Theme.dim)
                .padding(.top, 2)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
    }

    private func set(_ n: Int) {
        let clamped = min(12, max(1, n))
        withAnimation(.easeOut(duration: 0.12)) {
            store.setRunMode(.shared, sharedPool: clamped)
        }
    }

    private func stepButton(_ glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(Theme.mono(26, .bold))
                .foregroundStyle(Theme.fg)
                .frame(width: 56, height: 56)
                .overlay(Circle().stroke(Theme.fg, lineWidth: 1.4))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct CardView: View {
    let card: OnboardCard

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text(card.kicker)
                .font(Theme.mono(12, .bold))
                .tracking(3)
                .foregroundStyle(Theme.dim)
            Text(card.title)
                .font(Theme.mono(30, .bold))
                .foregroundStyle(Theme.fg)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Text(card.body)
                .font(Theme.mono(15))
                .foregroundStyle(Theme.dim)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
    }
}
