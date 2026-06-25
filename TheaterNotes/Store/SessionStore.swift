import Foundation
import SwiftUI

/// Single source of truth for the app: the cast template, all sessions, and
/// which session (if any) is currently live. Everything is persisted to a
/// JSON file in Documents; audio clips live in per-session subfolders.
@MainActor
final class SessionStore: ObservableObject {
    @Published var sessions: [ShowSession] = []
    @Published var castTemplate: [CastMember] = []
    @Published var activeSessionID: UUID?

    private let fm = FileManager.default

    init() {
        load()
    }

    // MARK: - Derived state

    var activeSession: ShowSession? {
        guard let id = activeSessionID else { return nil }
        return sessions.first { $0.id == id }
    }

    // MARK: - Sessions

    func startSession(title: String) {
        var session = ShowSession(title: title)
        session.cast = castTemplate
        sessions.append(session)
        activeSessionID = session.id
        save()
    }

    func endActiveSession() {
        guard let id = activeSessionID,
              let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].endedAt = Date()
        activeSessionID = nil
        save()
    }

    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if activeSessionID == id { activeSessionID = nil }
        try? fm.removeItem(at: sessionFolderURL(id))
        save()
    }

    /// A live, two-way binding to a session by id. Any mutation persists
    /// automatically, which keeps the active-session UI simple.
    func sessionBinding(_ id: UUID) -> Binding<ShowSession> {
        Binding(
            get: { self.sessions.first(where: { $0.id == id }) ?? ShowSession(title: "") },
            set: { newValue in
                if let idx = self.sessions.firstIndex(where: { $0.id == id }) {
                    self.sessions[idx] = newValue
                    self.save()
                }
            }
        )
    }

    // MARK: - Notes

    func addNote(_ note: Note, toSession id: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].notes.append(note)
        save()
    }

    func note(_ noteID: UUID, inSession id: UUID) -> Note? {
        sessions.first { $0.id == id }?.notes.first { $0.id == noteID }
    }

    func updateNote(_ note: Note, inSession id: UUID) {
        guard let si = sessions.firstIndex(where: { $0.id == id }),
              let ni = sessions[si].notes.firstIndex(where: { $0.id == note.id }) else { return }
        sessions[si].notes[ni] = note
        save()
    }

    func deleteNote(_ noteID: UUID, fromSession id: UUID) {
        guard let si = sessions.firstIndex(where: { $0.id == id }) else { return }
        if let note = sessions[si].notes.first(where: { $0.id == noteID }) {
            try? fm.removeItem(at: audioURL(sessionID: id, fileName: note.audioFileName))
        }
        sessions[si].notes.removeAll { $0.id == noteID }
        save()
    }

    // MARK: - File locations

    private var documentsURL: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var stateURL: URL {
        documentsURL.appendingPathComponent("state.json")
    }

    private func sessionFolderURL(_ id: UUID) -> URL {
        documentsURL.appendingPathComponent("Sessions/\(id.uuidString)", isDirectory: true)
    }

    /// URL for a clip, creating the session's audio folder if needed.
    func audioURL(sessionID: UUID, fileName: String) -> URL {
        let folder = sessionFolderURL(sessionID)
        if !fm.fileExists(atPath: folder.path) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder.appendingPathComponent(fileName)
    }

    // MARK: - Persistence

    private struct PersistedState: Codable {
        var sessions: [ShowSession] = []
        var castTemplate: [CastMember] = []
        var activeSessionID: UUID?
    }

    func save() {
        let state = PersistedState(sessions: sessions,
                                   castTemplate: castTemplate,
                                   activeSessionID: activeSessionID)
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            print("SessionStore save failed: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        sessions = state.sessions
        castTemplate = state.castTemplate
        activeSessionID = state.activeSessionID
    }
}
