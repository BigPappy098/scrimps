import SwiftUI

/// Compact note row shown in the live session list while notes stream in.
struct NoteRowCompact: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(note.assignedCastName ?? "Everyone",
                      systemImage: note.assignedCastName == nil ? "person.3.fill" : "person.fill")
                    .font(.caption.bold())
                    .foregroundStyle(note.assignedCastName == nil ? Color.secondary : Color.accentColor)
                Spacer()
                statusView
            }
            Text(displayText)
                .font(.body)
                .foregroundStyle(textColor)
        }
        .padding(.vertical, 2)
    }

    private var displayText: String {
        switch note.status {
        case .recording: return "● Recording…"
        case .transcribing: return "Transcribing…"
        case .failed: return "Couldn’t transcribe — tap History to play it back"
        case .done: return note.transcript.isEmpty ? "(no speech detected)" : note.transcript
        }
    }

    private var textColor: Color {
        switch note.status {
        case .done where !note.transcript.isEmpty: return .primary
        default: return .secondary
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch note.status {
        case .recording, .transcribing:
            ProgressView().controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
        case .done:
            Text(note.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
