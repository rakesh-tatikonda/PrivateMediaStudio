import SwiftUI
import SwiftData

struct SMBFTPConnectionSheet: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var viewModel: StreamsViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \ServerConnection.displayName) private var savedConnections: [ServerConnection]

    @State private var name = ""
    @State private var host = ""
    @State private var port = "445"
    @State private var protocolType: ServerProtocolType = .smb
    @State private var sharePath = ""
    @State private var username = ""
    @State private var password = ""

    @State private var selectedConnection: ServerConnection?
    @State private var filePath = ""
    @State private var fileTitle = ""

    var body: some View {
        NavigationStack {
            Form {
                if !savedConnections.isEmpty {
                    Section("Saved Servers") {
                        Picker("Server", selection: $selectedConnection) {
                            Text("None").tag(ServerConnection?.none)
                            ForEach(savedConnections) { connection in
                                Text(connection.displayName).tag(ServerConnection?.some(connection))
                            }
                        }
                        if selectedConnection != nil {
                            TextField("File path on share (e.g. Movies/film.mkv)", text: $filePath)
                                .autocorrectionDisabled()
                            TextField("Title", text: $fileTitle)
                            Button("Add File") { addFileFromSelectedConnection() }
                                .disabled(filePath.trimmingCharacters(in: .whitespaces).isEmpty || fileTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                        }

                        // Explicit management list with delete — a saved
                        // server's password lives in Keychain, so "just
                        // delete the app" isn't a real way to remove it;
                        // this is the actual removal path.
                        ForEach(savedConnections) { connection in
                            HStack {
                                Text(connection.displayName)
                                Spacer()
                                Text(connection.host).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .onDelete(perform: deleteConnections)
                    }
                }

                Section("New Connection") {
                    TextField("Name", text: $name)
                    Picker("Protocol", selection: $protocolType) {
                        ForEach(ServerProtocolType.allCases) { p in Text(p.displayName).tag(p) }
                    }
                    .onChange(of: protocolType) { _, newValue in port = String(newValue.defaultPort) }
                    TextField("Host or IP", text: $host)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                    TextField("Share name (SMB only)", text: $sharePath)
                    TextField("Username", text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("Password", text: $password)
                }

                Section {
                    Button("Save Connection") { saveConnection() }
                        .disabled(name.isEmpty || host.isEmpty)
                }
            }
            .navigationTitle("Connect to Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .tint(themeManager.currentTheme.accent)
        }
    }

    private func saveConnection() {
        guard let portNumber = Int(port) else { return }
        let saved = viewModel.saveServerConnection(
            name: name, host: host, port: portNumber, protocolType: protocolType,
            sharePath: sharePath.isEmpty ? nil : sharePath,
            username: username, password: password, modelContext: modelContext
        )
        if saved != nil {
            name = ""; host = ""; sharePath = ""; username = ""; password = ""
        }
    }

    private func addFileFromSelectedConnection() {
        guard let connection = selectedConnection else { return }
        viewModel.addFileFromServer(connection, filePath: filePath, title: fileTitle, modelContext: modelContext)
        dismiss()
    }

    private func deleteConnections(at offsets: IndexSet) {
        for index in offsets {
            let connection = savedConnections[index]
            if selectedConnection?.id == connection.id { selectedConnection = nil }
            viewModel.deleteServerConnection(connection, modelContext: modelContext)
        }
    }
}
