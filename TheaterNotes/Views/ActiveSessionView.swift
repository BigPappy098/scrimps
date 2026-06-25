import SwiftUI

/// The live session: a walky-talky button to capture notes, a streaming list
/// of what's been captured, and an End Show button.
struct ActiveSessionView: View {
    @EnvironmentObject var store: SessionStore
    @StateObject private var recorder = AudioRecorder()

    @State private var isPressing = false
    @State private var currentNoteID: UUID?
    @State private var showCastSheet = false
    @State private var showEndConfirm = false
    @State private var permissionDenied = false

    var body: some View {
        Group {
            if let id = store.activeSessionID, store.activeSession != nil {
                sessionContent(id)
            } else {
                ContentUnavailableView("No active show", systemImage: "mic.slash")
            }
        }
    }

    @ViewBuilder
    private func sessionContent(_ id: UUID) -> some View {
        let session = store.sessionBinding(id)
        VStack(spacing: 0) {
            notesList(session.wrappedValue)
            controls(id)
        }
        .navigationTitle(session.wrappedValue.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCastSheet = true
                } label: {
                    Label("Cast", systemImage: "person.3")
                }
            }
        }
        .sheet(isPresented: $showCastSheet) {
            NavigationStack {
                CastEditorView(
                    cast: session.cast,
                    title: "Show Cast",
                    footer: "Add or fix names mid-show. Changes apply to this session."
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showCastSheet = false }
                    }
                }
            }
        }
        .task { await ensurePermissions() }
        .alert("Microphone or Speech access denied", isPresented: $permissionDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enable Microphone and Speech Recognition for Theater Notes in Settings to record and transcribe notes.")
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func notesList(_ session: ShowSession) -> some View {
        if session.notes.isEmpty {
            ContentUnavailableView(
                "No notes yet",
                systemImage: "waveform",
                description: Text("Hold the button below and speak your note.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(session.notes.reversed()) { note in
                    NoteRowCompact(note: note)
                }
            }
            .listStyle(.plain)
        }
    }

    private func controls(_ id: UUID) -> some View {
        VStack(spacing: 16) {
            talkButton(id)
            Button(role: .destructive) {
                showEndConfirm = true
            } label: {
                Label("End Show", systemImage: "stop.circle")
            }
            .confirmationDialog("End this show session?", isPresented: $showEndConfirm, titleVisibility: .visible) {
                Button("End Show", role: .destructive) { store.endActiveSession() }
                Button("Keep Recording", role: .cancel) {}
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private func talkButton(_ id: UUID) -> some View {
        VStack(spacing: 10) {
            Circle()
                .fill(isPressing ? Color.red : Color.accentColor)
                .frame(width: 150, height: 150)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: isPressing ? "waveform" : "mic.fill")
                            .font(.system(size: 40))
                        Text(isPressing ? "Recording…" : "Hold to Talk")
                            .font(.subheadline.bold())
                    }
                    .foregroundStyle(.white)
                }
                .scaleEffect(isPressing ? 1.06 : 1.0)
                .shadow(radius: isPressing ? 12 : 4)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressing)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in startNote(id) }
                        .onEnded { _ in finishNote(id) }
                )
            Text("Say the cast name first, e.g. “Sarah, your cross is late.”")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Recording flow

    private func startNote(_ sessionID: UUID) {
        guard !isPressing else { return }
        isPressing = true

        let noteID = UUID()
        let fileName = "\(noteID.uuidString).m4a"
        let url = store.audioURL(sessionID: sessionID, fileName: fileName)

        let note = Note(id: noteID, audioFileName: fileName, status: .recording)
        store.addNote(note, toSession: sessionID)
        currentNoteID = noteID
        recorder.start(url: url)
    }

    private func finishNote(_ sessionID: UUID) {
        guard isPressing, let noteID = currentNoteID else { return }
        isPressing = false
        let duration = recorder.stop()
        currentNoteID = nil

        guard var note = store.note(noteID, inSession: sessionID) else { return }

        // Ignore accidental taps that didn't capture anything meaningful.
        if duration < 0.4 {
            store.deleteNote(noteID, fromSession: sessionID)
            return
        }

        note.duration = duration
        note.status = .transcribing
        store.updateNote(note, inSession: sessionID)

        let url = store.audioURL(sessionID: sessionID, fileName: note.audioFileName)
        let cast = store.activeSession?.cast ?? []
        let context = cast.flatMap { NameMatcher.contextualVariants($0.name) }

        Task { @MainActor in
            do {
                let raw = try await Transcriber.shared.transcribe(url: url, contextualStrings: context)
                let (assigned, text) = NameMatcher.match(transcript: raw, cast: cast)
                if var updated = store.note(noteID, inSession: sessionID) {
                    updated.rawTranscript = raw
                    updated.transcript = text.isEmpty ? raw : text
                    updated.assignedCastName = assigned
                    updated.status = .done
                    store.updateNote(updated, inSession: sessionID)
                }
            } catch {
                if var updated = store.note(noteID, inSession: sessionID) {
                    updated.status = .failed
                    store.updateNote(updated, inSession: sessionID)
                }
            }
        }
    }

    private func ensurePermissions() async {
        let mic = await AudioRecorder.requestPermission()
        let speech = await Transcriber.requestAuthorization()
        permissionDenied = !(mic && speech)
    }
}
