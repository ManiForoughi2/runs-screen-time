import SwiftUI

struct RootView: View {
    @EnvironmentObject var engine: RunEngine
    @EnvironmentObject var store: RunStore

    var body: some View {
        Group {
            if !store.onboarded {
                OnboardingView { }
            } else if !engine.authorized {
                PermissionView()
            } else {
                HomeView()
            }
        }
        .screenBackground()
        .animation(.easeInOut(duration: 0.25), value: store.onboarded)
        .animation(.easeInOut(duration: 0.25), value: engine.authorized)
    }
}
