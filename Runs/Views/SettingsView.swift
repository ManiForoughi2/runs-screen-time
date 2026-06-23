import SwiftUI
import FamilyControls
import ManagedSettings

struct SettingsView: View {
    @EnvironmentObject var engine: RunEngine
    @EnvironmentObject var store: RunStore
    @Environment(\.dismiss) private var dismiss

    @State private var selection = FamilyActivitySelection()
    @State private var showPicker = false
    @State private var editing: LimitConfig?
    @State private var showHowItWorks = false
    @State private var pendingLock: LockDuration?

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(store.limits) { limit in
                        LimitCard(limit: limit) { editing = limit }
                    }

                    Button {
                        selection.applicationTokens = Set(store.limits.map(\.token))
                        showPicker = true
                    } label: {
                        Text(store.limits.isEmpty ? "CHOOSE APPS" : "EDIT APP SELECTION")
                    }
                    .buttonStyle(OutlineButtonStyle())
                    .padding(.top, 4)

                    themeSection
                        .padding(.top, 26)

                    runModeSection
                        .padding(.top, 22)

                    lockSection
                        .padding(.top, 22)

                    Button {
                        showHowItWorks = true
                    } label: {
                        Text("how runs work")
                            .font(Theme.mono(13))
                            .foregroundStyle(Theme.dim)
                            .underline()
                            .padding(.vertical, 10)
                            .padding(.horizontal, 24)
                            .contentShape(Rectangle())
                    }
                    .padding(.top, 22)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .screenBackground()
        .overlay {
            if showHowItWorks {
                HowItWorksPopup { showHowItWorks = false }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showHowItWorks)
        .familyActivityPicker(isPresented: $showPicker, selection: $selection)
        .onChange(of: selection) { newValue in
            reconcile(newValue.applicationTokens)
        }
        .sheet(item: $editing) { limit in
            LimitEditor(limit: limit) { updated in
                store.upsert(updated)
                engine.reapplyBaselineShield()
            }
            .preferredColorScheme(store.themeMode.colorScheme)
        }
        .alert("Lock settings?", isPresented: lockConfirmBinding, presenting: pendingLock) { dur in
            Button("Lock \(dur.label)", role: .destructive) {
                store.applyLock(dur)
                pendingLock = nil
            }
            Button("Cancel", role: .cancel) { pendingLock = nil }
        } message: { dur in
            Text(dur == .forever
                 ? "You won't be able to loosen any settings. The only way to undo this is to delete the app."
                 : "You won't be able to loosen any settings for \(dur.label). You can still make them stricter.")
        }
    }

    private var lockConfirmBinding: Binding<Bool> {
        Binding(get: { pendingLock != nil }, set: { if !$0 { pendingLock = nil } })
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("THEME")
            SegmentedPicker(
                options: ThemeMode.allCases.map { ($0.label, $0) },
                selection: store.themeMode
            ) { store.setThemeMode($0) }
        }
    }

    private var runModeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("RUNS")
            SegmentedPicker(
                options: [("SHARED POOL", RunMode.shared), ("PER APP", RunMode.perApp)],
                selection: store.runMode
            ) { store.setRunMode($0, sharedPool: store.sharedRuns) }
            .disabled(store.isLocked)
            .opacity(store.isLocked ? 0.4 : 1)

            if store.runMode == .shared {
                HStack(spacing: 16) {
                    poolStepButton("–") { adjustPool(-1) }
                    Text("\(store.sharedRuns)")
                        .font(Theme.mono(28, .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.fg)
                        .frame(minWidth: 44)
                        .contentTransition(.numericText())
                    poolStepButton("+") { adjustPool(1) }
                    Text("runs / day")
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.dim)
                    Spacer()
                }
                .padding(.top, 4)
                .opacity(store.isLocked ? 0.4 : 1)
            }

            Text(store.runMode == .shared
                 ? "one pool, split across all your apps."
                 : "each app gets its own runs per day.")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.dim)
        }
    }

    private var lockSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("LOCK SETTINGS")
            SegmentedPicker(
                options: LockDuration.allCases.map { ($0.label, $0) },
                selection: currentLockSelection
            ) { picked in
                handleLockPick(picked)
            }
            Text(lockHint)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var currentLockSelection: LockDuration {
        guard store.isLocked else { return .off }
        return store.isLockedForever ? .forever : .week   // representative "on" segment
    }

    private var lockHint: String {
        if store.isLocked {
            return "\(store.lockRemainingText()). you can only make settings stricter until then."
        }
        return "lock so you can't loosen your limits. you can still tighten them."
    }

    private func handleLockPick(_ picked: LockDuration) {
        if store.isLocked {
            // already locked, store only honors extending; OFF or shorter is a no-op
            if picked == .off { return }
            store.applyLock(picked)
        } else {
            // fresh lock cant be undone early, confirm first
            if picked == .off { return }
            pendingLock = picked
        }
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(Theme.mono(11, .bold)).tracking(2).foregroundStyle(Theme.dim)
    }

    private func adjustPool(_ delta: Int) {
        guard !store.isLocked else { return }
        let n = min(12, max(1, store.sharedRuns + delta))
        withAnimation(.easeOut(duration: 0.12)) {
            store.setRunMode(.shared, sharedPool: n)
        }
    }

    private func poolStepButton(_ glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(Theme.mono(20, .bold))
                .foregroundStyle(Theme.fg)
                .frame(width: 42, height: 42)
                .overlay(Circle().stroke(Theme.fg, lineWidth: 1.2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(store.isLocked)
    }

    private var header: some View {
        HStack {
            Text("SETTINGS")
                .font(Theme.mono(18, .bold))
                .tracking(3)
                .foregroundStyle(Theme.fg)
            Spacer()
            Button { dismiss() } label: {
                Text("DONE")
                    .font(Theme.mono(14, .semibold))
                    .foregroundStyle(Theme.fg)
                    .padding(.vertical, 8)
                    .padding(.leading, 16)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 20)
    }

    private func reconcile(_ tokens: Set<ApplicationToken>) {
        var limits = store.limits

        limits.removeAll { !tokens.contains($0.token) }

        // empty label, rows use Apples real name; label only nicknames the Live Activity
        let existing = Set(limits.map(\.token))
        for token in tokens where !existing.contains(token) {
            limits.append(LimitConfig(
                token: token,
                label: "",
                minutesPerRun: 3,
                runsPerDay: 4
            ))
        }

        store.setLimits(limits)
        engine.reapplyBaselineShield()
    }
}

private struct LimitCard: View {
    @EnvironmentObject var store: RunStore
    let limit: LimitConfig
    let onEdit: () -> Void

    private var subtitle: String {
        store.runMode == .shared
            ? "\(limit.minutesPerRun) min / run"
            : "\(limit.minutesPerRun) min  ·  \(limit.runsPerDay) runs/day"
    }

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    // Label(token) renders Apples real icon + name
                    Label(limit.token)
                        .labelStyle(.titleAndIcon)
                        .font(Theme.mono(17, .bold))
                        .foregroundStyle(Theme.fg)
                    Text(subtitle)
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            .padding(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

private struct HowItWorksPopup: View {
    var onClose: () -> Void

    private let beats: [(String, String)] = [
        ("A RUN", "tap an app and the clock starts. it opens for a few minutes, with a timer counting down on your lock screen."),
        ("WHEN IT ENDS", "the app locks back up. out of runs for the day? it stays locked until tomorrow."),
        ("YOUR CALL", "you set how many runs and how many minutes each, per app. change them whenever.")
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }

            VStack(alignment: .leading, spacing: 22) {
                Text("HOW RUNS WORK")
                    .font(Theme.mono(15, .bold))
                    .tracking(3)
                    .foregroundStyle(Theme.fg)

                ForEach(beats.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(beats[i].0)
                            .font(Theme.mono(11, .bold))
                            .tracking(2)
                            .foregroundStyle(Theme.dim)
                        Text(beats[i].1)
                            .font(Theme.mono(13))
                            .foregroundStyle(Theme.fg)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button { onClose() } label: {
                    Text("GOT IT")
                }
                .buttonStyle(OutlineButtonStyle(filled: true))
                .padding(.top, 2)
            }
            .padding(26)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Theme.bg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(Theme.hairline, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 28)
        }
    }
}
