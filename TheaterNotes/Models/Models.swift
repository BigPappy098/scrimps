import Foundation

/// A person in the show. Names are used both as recognition hints for the
/// speech engine and to attribute each note to the right person.
struct CastMember: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var role: String = ""
}

/// Lifecycle of a single spoken note, from the moment the button is pressed
/// through transcription.
enum NoteStatus: String, Codable {
    case recording
    case transcribing
    case done
    case failed
}

/// One push-to-talk note. The audio lives on disk; `audioFileName` is the
/// file name within the owning session's audio folder.
struct Note: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var audioFileName: String
    var duration: TimeInterval = 0
    /// Cleaned note text shown to the user (cast name stripped off the front).
    var transcript: String = ""
    /// Exactly what the speech engine returned, kept for reference / re-matching.
    var rawTranscript: String = ""
    /// The cast member this note is for. `nil` means it applies to everyone.
    var assignedCastName: String?
    var status: NoteStatus = .recording
}

/// A rehearsal / tech session. Holds its own snapshot of the cast (copied from
/// the template at start) plus every note captured during the session.
struct ShowSession: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var createdAt: Date = Date()
    var endedAt: Date?
    var cast: [CastMember] = []
    var notes: [Note] = []

    var isActive: Bool { endedAt == nil }
}
