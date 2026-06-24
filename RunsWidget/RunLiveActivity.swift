import ActivityKit
import WidgetKit
import SwiftUI

struct RunLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            LockScreenRunView(context: context)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RUNNING")
                            .font(.system(.caption2, design: .monospaced).weight(.bold))
                            .tracking(2)
                            .foregroundStyle(.white.opacity(0.5))
                        Text(context.attributes.appLabel)
                            .font(.system(.title3, design: .monospaced).weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.startedAt...context.state.endsAt, countsDown: true)
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("\(context.attributes.runsLeftAfter) runs left after this")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }
            } compactLeading: {
                // small dot keeps the leading region non-empty so iOS reliably
                // renders the compact pill (an empty leading/trailing pair can
                // make the island refuse to draw the timer at all)
                Circle()
                    .fill(.white)
                    .frame(width: 7, height: 7)
            } compactTrailing: {
                CompactTimer(state: context.state)
            } minimal: {
                // minimal is a single round slot (this app collapses here when it
                // shares the island) so MM:SS cant fit, show the glyph instead
                Image(systemName: "timer")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .keylineTint(.white)
        }
    }
}

// Compact / minimal pill timer. The system gives these regions a tiny budget,
// so we pin a fixed mono width and count down with .timer. No scale-to-fit fight
// (that combo flickered and let the pill stretch toward full width).
private struct CompactTimer: View {
    let state: RunActivityAttributes.ContentState

    var body: some View {
        Text(timerInterval: state.startedAt...state.endsAt, countsDown: true)
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .frame(width: 44)
    }
}

private struct LockScreenRunView: View {
    let context: ActivityViewContext<RunActivityAttributes>

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RUNNING")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.5))
                    Text(context.attributes.appLabel)
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 8)
                Text(timerInterval: context.state.startedAt...context.state.endsAt, countsDown: true)
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.white)
            }

            ProgressView(timerInterval: context.state.startedAt...context.state.endsAt, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(.white)
            .labelsHidden()
        }
        .padding(20)
    }
}
