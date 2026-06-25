import SwiftUI

/// "History" tab — every show session, newest first.
struct SessionListView: View {
    @EnvironmentObject var store: SessionStore

    private var sortedSessions: [ShowSession] {
        store.sessions.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.sessions.isEmpty {
                    ContentUnavailableView(
                        "No shows yet",
                        systemImage: "clock",
                        description: Text("Start a show in the Record tab to capture notes.")
                    )
                } else {
                    List {
                        ForEach(sortedSessions) { session in
                            NavigationLink(value: session.id) {
                                row(session)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: UUID.self) { id in
                SessionDetailView(sessionID: id)
            }
        }
    }

    private func row(_ session: ShowSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.title).font(.headline)
                if session.isActive {
                    Text("LIVE")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("^[\(session.notes.count) note](inflect: true)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func delete(at offsets: IndexSet) {
        let ids = offsets.map { sortedSessions[$0].id }
        for id in ids { store.deleteSession(id) }
    }
}
