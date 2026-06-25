import SwiftUI

/// Reusable editor for a list of cast members. Used for both the global cast
/// template and an in-progress session's cast.
struct CastEditorView: View {
    @Binding var cast: [CastMember]
    var title: String
    var footer: String?

    @State private var newName = ""
    @State private var newRole = ""

    var body: some View {
        List {
            Section {
                if cast.isEmpty {
                    Text("No cast members yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach($cast) { $member in
                        VStack(alignment: .leading, spacing: 2) {
                            TextField("Name", text: $member.name)
                            TextField("Role (optional)", text: $member.role)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { cast.remove(atOffsets: $0) }
                }
            } header: {
                Text("Cast Members")
            } footer: {
                if let footer { Text(footer) }
            }

            Section("Add Member") {
                TextField("Name", text: $newName)
                TextField("Role (optional)", text: $newRole)
                Button {
                    addMember()
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .disabled(newName.trimmed.isEmpty)
            }
        }
        .navigationTitle(title)
        .toolbar { EditButton() }
    }

    private func addMember() {
        cast.append(CastMember(name: newName.trimmed, role: newRole.trimmed))
        newName = ""
        newRole = ""
    }
}

/// The "Cast" tab — edits the reusable template applied to new shows.
struct CastListView: View {
    @EnvironmentObject var store: SessionStore

    var body: some View {
        NavigationStack {
            CastEditorView(
                cast: $store.castTemplate,
                title: "Cast",
                footer: "This cast list is used as a reference for new shows and helps match each note to the right person."
            )
            .onChange(of: store.castTemplate) { _, _ in store.save() }
        }
    }
}
