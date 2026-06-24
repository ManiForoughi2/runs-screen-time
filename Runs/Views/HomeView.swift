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
    @State private var selection = FamilyActivitySelection()

    private var hasActiveRun: Bool { store.activeRun != nil }
    // in shared mode every row draws the same pool, so we lift it to one bar
    private var showsPoolBar: Bool {
        store.runMode == .shared && !store.limits.isEmpty && !hasActiveRun
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
            reconcile(newValue.applicationTokens)
        }
    }

    private func reconcile(_ tokens: Set<ApplicationToken>) {
        var limits = store.limits
        limits.removeAll { !tokens.contains($0.token) }
        let existing = Set(limits.map(\.token))
        for token in tokens where !existing.contains(token) {
            limits.append(LimitConfig(token: token, label: "", minutesPerRun: 3, runsPerDay: 4))
        }
        store.setLimits(limits)
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
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("no apps yet.")
                .font(Theme.mono(15))
                .foregroundStyle(Theme.dim)
            Button {
                selection.applicationTokens = Set(store.limits.map(\.token))
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
    // shared mode shows one pool bar instead, so per-row pips are redundant
    private var showsPips: Bool { store.runMode != .shared }

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
                Text(left > 0 ? "START RUN" : "DONE FOR TODAY")
            }
            .buttonStyle(OutlineButtonStyle(filled: left > 0))
            .disabled(left == 0 || !store.canStartRun(for: limit))
            .opacity(left == 0 ? 0.4 : 1)
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
