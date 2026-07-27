import SwiftUI
import FamilyControls
import ManagedSettings
import StoreKit

struct HomeView: View {
    @EnvironmentObject var engine: RunEngine
    @EnvironmentObject var store: RunStore
    @Environment(\.requestReview) private var requestReview
    @State private var showSettings = false
    @State private var showPicker = false
    @State private var breatheTarget: Platform?
    // includeEntireCategory expands a picked category (e.g. Social) into its
    // individual apps so each gets its own limit instead of being ignored
    @State private var selection = FamilyActivitySelection(includeEntireCategory: true)

    private var hasActiveRun: Bool { store.activeRun != nil }
    // in shared mode every row draws the same pool, so we lift it to one bar.
    // full block always has 0 in the pool, so the bar is hidden then.
    // solo breathe has no budget, so there's no pool to show either.
    private var showsPoolBar: Bool {
        store.runMode == .shared && !store.limits.isEmpty && !hasActiveRun
            && !store.fullBlock && !store.breatheSolo
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if hasActiveRun, let run = store.activeRun {
                ActiveRunView(run: run)
                    .transition(.opacity)
            } else if store.limits.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .screenBackground()
        .safeAreaInset(edge: .bottom) {
            if showsPoolBar {
                PoolBar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: hasActiveRun)
        .onChange(of: hasActiveRun) { active in
            // ask for review on run-end, never during onboarding
            if !active { maybeAskForReview() }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(engine)
                .environmentObject(store)
                .preferredColorScheme(store.themeMode.colorScheme)
        }
        .familyActivityPicker(isPresented: $showPicker, selection: $selection)
        .onChange(of: selection) { newValue in
            reconcile(newValue)
        }
        .fullScreenCover(item: $breatheTarget) { platform in
            BreatheView(platform: platform)
                .environmentObject(engine)
                .environmentObject(store)
                .preferredColorScheme(store.themeMode.colorScheme)
        }
    }

    // blocked sites that can be breathed open (paired automatically or toggled
    // in settings). chrome/brave on iOS can't run extensions, so the breathe
    // for websites happens here in the app.
    private var webPlatforms: [Platform] {
        guard store.webBlocking else { return [] }
        return Platform.all.filter { store.isPlatformBlocked($0.id) }
            + store.customSites.map(Platform.custom)
    }

    private func reconcile(_ sel: FamilyActivitySelection) {
        var limits = store.limits
        limits.removeAll { !sel.applicationTokens.contains($0.token) }
        let existing = Set(limits.map(\.token))
        for token in sel.applicationTokens where !existing.contains(token) {
            limits.append(LimitConfig(token: token, label: "", minutesPerRun: 3, runsPerDay: 4))
        }
        store.setLimits(limits)
        store.setWebDomainTokens(sel.webDomainTokens)
        engine.reapplyBaselineShield()
    }

    private func maybeAskForReview() {
        guard store.shouldRequestReviewNow() else { return }
        // delay so review sheet doesnt fight the run-end transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            requestReview()
        }
    }

    private var header: some View {
        HStack {
            Text("RUNS")
                .font(Theme.mono(18, .bold))
                .tracking(3)
                .foregroundStyle(Theme.fg)
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.fg)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(hasActiveRun)
            .opacity(hasActiveRun ? 0.3 : 1)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(store.limits) { limit in
                    RunRow(limit: limit)
                }

                if !webPlatforms.isEmpty {
                    webCard
                        .padding(.top, 10)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
    }

    private var webCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WEB")
                .font(Theme.mono(11, .bold))
                .tracking(2)
                .foregroundStyle(Theme.dim)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(webPlatforms) { platform in
                    let open = store.webSessionEndsAt(platform.id) != nil
                    let canStart = store.canStartWebSession(for: platform)
                    Button {
                        if !open && canStart { breatheTarget = platform }
                    } label: {
                        Text(open ? "\(platform.name.uppercased()) · OPEN" : platform.name.uppercased())
                            .font(Theme.mono(11, .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .foregroundStyle(open ? Theme.bg : Theme.fg)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(open ? Theme.fg : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(open ? Theme.fg : Theme.hairline, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .opacity(open || canStart ? 1 : 0.4)
                }
            }

            Text("sites rest in every browser. tap to breathe one open.")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.dim)
        }
        .padding(16)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("no apps yet.")
                .font(Theme.mono(15))
                .foregroundStyle(Theme.dim)
            Button {
                selection.applicationTokens = Set(store.limits.map(\.token))
                selection.webDomainTokens = store.webDomainTokens
                showPicker = true
            } label: {
                Text("CHOOSE APPS")
            }
            .buttonStyle(OutlineButtonStyle())
            .padding(.horizontal, 60)
            Spacer()
            Spacer()
        }
    }
}

private struct RunRow: View {
    @EnvironmentObject var engine: RunEngine
    @EnvironmentObject var store: RunStore
    let limit: LimitConfig

    private var left: Int { store.runsLeft(for: limit) }
    private var total: Int { store.runsTotal(for: limit) }
    // shared mode shows one pool bar instead, so per-row pips are redundant.
    // full block zeroes every run, so pips would just be an empty row.
    // solo breathe has no budget, so pips are meaningless.
    private var showsPips: Bool { store.runMode != .shared && !store.fullBlock && !store.breatheSolo }

    private var startEnabled: Bool { store.canStartRun(for: limit) }

    private var startLabel: String {
        if store.fullBlock { return "BLOCKED" }
        if store.breatheSolo { return "OPEN" }
        return left > 0 ? "START RUN" : "DONE FOR TODAY"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                // Label(token) renders Apples real icon + name, token is opaque otherwise
                Label(limit.token)
                    .labelStyle(.titleAndIcon)
                    .font(Theme.mono(22, .bold))
                    .foregroundStyle(Theme.fg)
                Spacer()
                Text("\(limit.minutesPerRun) MIN / RUN")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.dim)
            }

            if showsPips {
                HStack(spacing: 6) {
                    // up to 9 runs fit as dots; 10+ would compress so we go numeric
                    if total < Theme.dotsOnlyThreshold {
                        ForEach(0..<total, id: \.self) { i in
                            Circle()
                                .fill(i < left ? Theme.fg : Color.clear)
                                .overlay(Circle().stroke(Theme.fg, lineWidth: 1))
                                .frame(width: 12, height: 12)
                        }
                        Spacer()
                        // 7-9 runs: dots get tight, so the count text is dropped
                        if total < Theme.dotsWithCountThreshold {
                            Text("\(left)/\(total) LEFT")
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.dim)
                        }
                    } else {
                        Text("\(left) / \(total) LEFT")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.dim)
                        Spacer()
                    }
                }
            }

            Button {
                engine.startRun(for: limit)
            } label: {
                Text(startLabel)
            }
            .buttonStyle(OutlineButtonStyle(filled: startEnabled))
            .disabled(!startEnabled)
            .opacity(startEnabled ? 1 : 0.4)
        }
        .padding(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }
}

// shared pool, shown once floating at the bottom instead of per app row
private struct PoolBar: View {
    @EnvironmentObject var store: RunStore

    private var left: Int { max(0, store.sharedRuns - store.sharedUsed) }
    private var total: Int { store.sharedRuns }

    var body: some View {
        HStack(spacing: 14) {
            Text("RUNS")
                .font(Theme.mono(15, .semibold))
                .tracking(2)
                .foregroundStyle(Theme.dim)

            // up to 9 runs fit as dots; 10+ would compress so we go numeric
            if total < Theme.dotsOnlyThreshold {
                HStack(spacing: 9) {
                    ForEach(0..<total, id: \.self) { i in
                        Circle()
                            .fill(i < left ? Theme.fg : Color.clear)
                            .overlay(Circle().stroke(Theme.fg, lineWidth: 1.5))
                            .frame(width: 18, height: 18)
                    }
                }

                Spacer()

                // 7-9 runs: dots get tight, so the count text is dropped
                if total < Theme.dotsWithCountThreshold {
                    Text("\(left)/\(total) LEFT")
                        .font(Theme.mono(15))
                        .foregroundStyle(Theme.dim)
                }
            } else {
                Spacer()

                Text("\(left) / \(total) LEFT")
                    .font(Theme.mono(15))
                    .foregroundStyle(Theme.dim)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Theme.hairline, lineWidth: 1.2)
                )
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}
