import SwiftUI

/// Screen shown when no session is live: name the show and start it.
struct StartSessionView: View {
    @EnvironmentObject var store: SessionStore
    @State private var title = ""

    var body: some View {
        Form {
            Section("New Show Session") {
                TextField("Show / session title", text: $title)
                    .submitLabel(.done)
            }

            Section("Cast (\(store.castTemplate.count))") {
                if store.castTemplate.isEmpty {
                    Text("No cast added yet. Add names in the Cast tab so notes can be matched to people. You can still record without a cast — those notes go to “Everyone”.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.castTemplate) { member in
                        HStack {
                            Text(member.name)
                            if !member.role.isEmpty {
                                Text(member.role)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    store.startSession(title: title.trimmed)
                    title = ""
                } label: {
                    Label("Start Show", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmed.isEmpty)
            }
        }
        .navigationTitle("Theater Notes")
    }
}
