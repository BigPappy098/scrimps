import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            RecordTab()
                .tabItem { Label("Record", systemImage: "mic.circle.fill") }
            CastListView()
                .tabItem { Label("Cast", systemImage: "person.3.fill") }
            SessionListView()
                .tabItem { Label("History", systemImage: "clock.fill") }
        }
    }
}

/// Shows the live session if one is running, otherwise the start screen.
private struct RecordTab: View {
    @EnvironmentObject var store: SessionStore

    var body: some View {
        NavigationStack {
            if store.activeSession != nil {
                ActiveSessionView()
            } else {
                StartSessionView()
            }
        }
    }
}
