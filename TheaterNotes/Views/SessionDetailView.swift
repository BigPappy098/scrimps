import SwiftUI

/// A group of notes for one recipient (a cast member, or "Everyone").
private struct NoteGroup: Identifiable {
    let id: String
    let title: String
    let notes: [Note]
}

/// Full review of a session: notes grouped by who they're for, with playback,
/// inline editing, reassignment, and text export.
struct SessionDetailView: View {
    @EnvironmentObject var store: SessionStore
    @StateObject private var player = AudioPlayer()
    let sessionID: UUID

    private var session: ShowSession? {
        store.sessions.first { $0.id == sessionID }
    }

    var body: some View {
        Group {
            if let session {
                content(session)
            } else {
                ContentUnavailableView("Session not found", systemImage: "questionmark.folder")
            }
        }
    }

    @ViewBuilder
    private func content(_ session: ShowSession) -> some View {
        Group {
            if session.notes.isEmpty {
                ContentUnavailableView(
                    "No notes",
                    systemImage: "doc.text",
                    description: Text("This session didn't capture any notes.")
                )
            } else {
                List {
                    ForEach(groups(session)) { group in
                        Section(group.title) {
                            ForEach(group.notes) { note in
                                NoteDetailRow(
                                    sessionID: sessionID,
                                    note: note,
                                    cast: session.cast,
                                    player: player
                                )
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: exportText(session)) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    // MARK: - Grouping

    private func groups(_ session: ShowSession) -> [NoteGroup] {
        var result: [NoteGroup] = []

        let everyone = session.notes
            .filter { $0.assignedCastName == nil }
            .sorted { $0.createdAt < $1.createdAt }
        if !everyone.isEmpty {
            result.append(NoteGroup(id: "__everyone__", title: "Everyone", notes: everyone))
        }

        for member in session.cast {
            let notes = session.notes
                .filter { $0.assignedCastName == member.name }
                .sorted { $0.createdAt < $1.createdAt }
            guard !notes.isEmpty else { continue }
            let title = member.role.isEmpty ? member.name : "\(member.name) — \(member.role)"
            result.append(NoteGroup(id: member.id.uuidString, title: title, notes: notes))
        }

        // Notes assigned to a name that's no longer in the cast.
        let known = Set(session.cast.map { $0.name })
        let orphans = Set(session.notes.compactMap { $0.assignedCastName }).subtracting(known)
        for name in orphans.sorted() {
            let notes = session.notes
                .filter { $0.assignedCastName == name }
                .sorted { $0.createdAt < $1.createdAt }
            result.append(NoteGroup(id: "orphan_\(name)", title: name, notes: notes))
        }

        return result
    }

    // MARK: - Export

    private func exportText(_ session: ShowSession) -> String {
        var lines: [String] = [
            session.title,
            session.createdAt.formatted(date: .long, time: .shortened),
            String(repeating: "=", count: 28)
        ]
        for group in groups(session) {
            lines.append("")
            lines.append("\(group.title.uppercased()):")
            for note in group.notes {
                let text = note.transcript.trimmed.isEmpty ? "(no transcript)" : note.transcript.trimmed
                lines.append("  • \(text)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// A single editable note in the detail view.
private struct NoteDetailRow: View {
    @EnvironmentObject var store: SessionStore
    let sessionID: UUID
    let note: Note
    let cast: [CastMember]
    @ObservedObject var player: AudioPlayer

    private var audioURL: URL {
        store.audioURL(sessionID: sessionID, fileName: note.audioFileName)
    }

    private var isPlaying: Bool {
        player.playingURL == audioURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Transcript", text: transcriptBinding, axis: .vertical)

            HStack(spacing: 18) {
                Button {
                    player.toggle(audioURL)
                } label: {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)

                Menu {
                    Button {
                        reassign(nil)
                    } label: {
                        Label("Everyone", systemImage: "person.3")
                    }
                    ForEach(cast) { member in
                        Button(member.name) { reassign(member.name) }
                    }
                } label: {
                    Label(note.assignedCastName ?? "Everyone", systemImage: "person.crop.circle")
                        .font(.caption)
                }

                Spacer()

                Text(note.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .swipeActions {
            Button(role: .destructive) {
                store.deleteNote(note.id, fromSession: sessionID)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var transcriptBinding: Binding<String> {
        Binding(
            get: { note.transcript },
            set: { newValue in
                var updated = note
                updated.transcript = newValue
                store.updateNote(updated, inSession: sessionID)
            }
        )
    }

    private func reassign(_ name: String?) {
        var updated = note
        updated.assignedCastName = name
        store.updateNote(updated, inSession: sessionID)
    }
}
