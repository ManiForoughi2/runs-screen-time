import SwiftUI
import FamilyControls
import ManagedSettings

struct SettingsView: View {
    @EnvironmentObject var engine: RunEngine
    @EnvironmentObject var store: RunStore
    @Environment(\.dismiss) private var dismiss

    // includeEntireCategory expands a picked category (e.g. Social) into its
    // individual apps so each gets its own limit instead of being ignored
    @State private var selection = FamilyActivitySelection(includeEntireCategory: true)
    @State private var showPicker = false
    @State private var editing: LimitConfig?
    @State private var showHowItWorks = false
    @State private var pendingLock: LockDuration?
    @State private var confirmEmergency = false

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 12) {
                    themeSection

                    runModeSection
                        .padding(.top, 26)

                    fullBlockSection
                        .padding(.top, 26)

                    breatheSection
                        .padding(.top, 26)

                    webSection
                        .padding(.top, 26)

                    if !store.limits.isEmpty {
                        VStack(spacing: 12) {
                            ForEach(store.limits) { limit in
                                LimitCard(limit: limit) { editing = limit }
                            }
                        }
                        .padding(.top, 26)
                    }

                    Button {
                        selection.applicationTokens = Set(store.limits.map(\.token))
                        selection.webDomainTokens = store.webDomainTokens
                        showPicker = true
                    } label: {
                        Text(store.limits.isEmpty ? "CHOOSE APPS" : "EDIT APP SELECTION")
                    }
                    .buttonStyle(OutlineButtonStyle())
                    .padding(.top, store.limits.isEmpty ? 26 : 4)

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
            reconcile(newValue)
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
        .alert("Use an emergency?", isPresented: $confirmEmergency) {
            Button("Unlock \(Emergency.minutes) min", role: .destructive) {
                engine.startEmergencyRun()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This opens all your blocked apps for \(Emergency.minutes) minutes, then they lock again. You get \(Emergency.total) emergencies every 7 days.")
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

    private var fullBlockSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("FULL BLOCK")
            SegmentedPicker(
                options: [("OFF", false), ("ON", true)],
                selection: store.fullBlock
            ) { on in
                withAnimation(.easeOut(duration: 0.15)) {
                    store.setFullBlock(on)
                }
                engine.reapplyBaselineShield()
            }
            // once locked you can turn full block ON (tightening) but not OFF
            .disabled(store.isLocked && store.fullBlock)
            .opacity(store.isLocked && store.fullBlock ? 0.4 : 1)

            Text(store.fullBlock
                 ? "your apps stay locked with no runs. use an emergency below only when you really need in."
                 : "turn on to fully block your apps. no runs, emergency only.")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)

            if store.fullBlock {
                emergencyRow
                    .padding(.top, 6)
            }
        }
    }

    private var breatheSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("BREATHE")
            SegmentedPicker(
                options: [("OFF", 0), ("3S", 3), ("5S", 5), ("10S", 10)],
                selection: store.breatheSeconds
            ) { store.setBreatheSeconds($0) }

            if store.breatheSeconds > 0 {
                SegmentedPicker(
                    options: [("WITH RUNS", false), ("JUST BREATHE", true)],
                    selection: store.breatheSolo
                ) { on in
                    store.setBreatheSolo(on)
                    engine.reapplyBaselineShield()
                }
                // once locked you can go back to runs (tightening) but not drop the budget
                .disabled(store.isLocked && !store.breatheSolo)
                .opacity(store.isLocked && !store.breatheSolo ? 0.4 : 1)
            }

            Text(breatheHint)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var breatheHint: String {
        if store.breatheSeconds == 0 {
            return "the shield is a wall. runs only start from this app."
        }
        return store.breatheSolo
            ? "no runs, no budget. every open is one slow breath, and the app rests again after its minutes."
            : "a resting app's shield offers one slow breath. breathe, then the run starts right there."
    }

    private var webSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("WEBSITES")
            SegmentedPicker(
                options: [("OFF", false), ("ON", true)],
                selection: store.webBlocking
            ) { on in
                store.setWebBlocking(on)
                engine.reapplyBaselineShield()
            }
            // once locked web blocking can be turned ON (tightening) but not OFF
            .disabled(store.isLocked && store.webBlocking)
            .opacity(store.isLocked && store.webBlocking ? 0.4 : 1)

            Text(store.webBlocking
                 ? "each app's website rests too, in every browser — instagram locks instagram.com. matched automatically, or tap sites below. breathe a site open from home."
                 : "apps lock, their websites stay open in the browser.")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)

            if store.webBlocking {
                platformChips
                    .padding(.top, 4)

                if !store.webDomainTokens.isEmpty {
                    Text("+\(store.webDomainTokens.count) site\(store.webDomainTokens.count == 1 ? "" : "s") from the app picker")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.dim)
                }
            }
        }
    }

    private var platformChips: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
            ForEach(Platform.all) { platform in
                let on = store.isPlatformBlocked(platform.id)
                Button {
                    store.togglePlatform(platform.id)
                    engine.reapplyBaselineShield()
                } label: {
                    Text(platform.name.uppercased())
                        .font(Theme.mono(11, .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(on ? Theme.bg : Theme.dim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(on ? Theme.fg : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(on ? Theme.fg : Theme.hairline, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emergencyRow: some View {
        let left = store.emergenciesLeft
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(0..<Emergency.total, id: \.self) { i in
                    Circle()
                        .fill(i < left ? Theme.fg : Color.clear)
                        .overlay(Circle().stroke(Theme.fg, lineWidth: 1.2))
                        .frame(width: 12, height: 12)
                }
                Text("\(left)/\(Emergency.total) EMERGENCIES")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.dim)
                Spacer()
            }

            Button {
                confirmEmergency = true
            } label: {
                Text(left > 0 ? "EMERGENCY · \(Emergency.minutes) MIN" : "NO EMERGENCIES LEFT")
            }
            .buttonStyle(OutlineButtonStyle(filled: left > 0))
            .disabled(!store.canStartEmergency())
            .opacity(store.canStartEmergency() ? 1 : 0.4)

            if let refill = store.nextEmergencyRefill() {
                Text(emergencyRefillText(refill))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.dim)
            }
        }
    }

    private func emergencyRefillText(_ date: Date) -> String {
        let secs = max(0, date.timeIntervalSinceNow)
        let days = Int(secs / 86_400)
        let hours = Int((secs.truncatingRemainder(dividingBy: 86_400)) / 3600)
        if days >= 1 { return "next emergency in \(days)d \(hours)h" }
        let mins = Int((secs.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours >= 1 { return "next emergency in \(hours)h \(mins)m" }
        return "next emergency in \(mins)m"
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

    private func reconcile(_ sel: FamilyActivitySelection) {
        var limits = store.limits

        limits.removeAll { !sel.applicationTokens.contains($0.token) }

        // empty label, rows use Apples real name; label only nicknames the Live Activity
        let existing = Set(limits.map(\.token))
        for token in sel.applicationTokens where !existing.contains(token) {
            limits.append(LimitConfig(
                token: token,
                label: "",
                minutesPerRun: 3,
                runsPerDay: 4
            ))
        }

        store.setLimits(limits)
        store.setWebDomainTokens(sel.webDomainTokens)
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
