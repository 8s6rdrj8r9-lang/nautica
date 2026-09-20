import SwiftUI

/// Floating dialog for connecting to remote network servers (Finder ⌘K style).
struct ConnectToServerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onConnected: ((URL) -> Void)?

    @State private var connectionService = ServerConnectionService.shared
    @State private var serverAddress: String = ""
    @State private var selectedFavorite: String? = nil
    @State private var isConnecting: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "server.rack")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect to Server")
                        .font(.headline)
                    Text("Enter a server address such as smb://server.local or nfs://192.168.1.100")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Server Address Input
            VStack(alignment: .leading, spacing: 6) {
                Text("Server Address:")
                    .font(.caption)
                    .fontWeight(.medium)

                HStack {
                    TextField("smb://server.local/share", text: $serverAddress)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(connect)

                    // Protocol Quick-Select Menu
                    Menu {
                        Button("smb:// (Windows / Mac / Samba)") { setProtocol("smb://") }
                        Button("afp:// (Apple Filing Protocol)") { setProtocol("afp://") }
                        Button("nfs:// (Network File System)") { setProtocol("nfs://") }
                        Button("vnc:// (Screen Sharing)") { setProtocol("vnc://") }
                        Button("http:// (WebDAV)") { setProtocol("http://") }
                        Button("https:// (Secure WebDAV)") { setProtocol("https://") }
                        Button("ftp:// (File Transfer Protocol)") { setProtocol("ftp://") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 24)

                    // Add to Favorites Button (+)
                    Button(action: addFavorite) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Add current address to Favorite Servers")
                }
            }

            // Favorite & Recent Servers
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Favorite Servers:")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    if !connectionService.recentServers.isEmpty {
                        Menu("Recent Servers") {
                            ForEach(connectionService.recentServers, id: \.self) { recent in
                                Button(recent) {
                                    serverAddress = recent
                                }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .font(.caption)
                    }
                }

                // Favorites Table / List
                List(selection: $selectedFavorite) {
                    ForEach(connectionService.favoriteServers, id: \.self) { fav in
                        Text(fav)
                            .font(.system(size: 12, design: .monospaced))
                            .tag(fav)
                            .onTapGesture(count: 2) {
                                serverAddress = fav
                                connect()
                            }
                    }
                }
                .frame(height: 120)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                // Bottom toolbar for favorites: Remove (-) and Discovered local servers
                HStack {
                    Button(action: removeSelectedFavorite) {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedFavorite == nil)
                    .help("Remove selected server from favorites")

                    Spacer()

                    if !connectionService.discoveredServers.isEmpty {
                        Menu("Available Local Servers (\(connectionService.discoveredServers.count))") {
                            ForEach(connectionService.discoveredServers, id: \.self) { name in
                                Button("\(name).local") {
                                    serverAddress = "smb://\(name).local"
                                }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .font(.caption)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Bottom Buttons
            HStack {
                Button("Browse…") {
                    // Opens Network in Finder / Nautica
                    onConnected?(URL(fileURLWithPath: "/Volumes"))
                    dismiss()
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(action: connect) {
                    if isConnecting {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 40)
                    } else {
                        Text("Connect")
                            .frame(minWidth: 60)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isConnecting || serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 6)
        }
        .padding(18)
        .frame(width: 480)
        .onChange(of: selectedFavorite) {
            if let selectedFavorite {
                serverAddress = selectedFavorite
            }
        }
    }

    private func setProtocol(_ proto: String) {
        if let colonSlash = serverAddress.range(of: "://") {
            serverAddress = proto + String(serverAddress[colonSlash.upperBound...])
        } else {
            serverAddress = proto + serverAddress
        }
    }

    private func addFavorite() {
        connectionService.addFavorite(serverAddress)
    }

    private func removeSelectedFavorite() {
        guard let selectedFavorite,
              let idx = connectionService.favoriteServers.firstIndex(of: selectedFavorite) else { return }
        connectionService.removeFavorite(at: idx)
        self.selectedFavorite = nil
    }

    private func connect() {
        let target = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        isConnecting = true
        errorMessage = nil

        Task {
            do {
                if let mountedURL = try await connectionService.connect(to: target) {
                    await MainActor.run {
                        isConnecting = false
                        onConnected?(mountedURL)
                        dismiss()
                    }
                } else {
                    await MainActor.run {
                        isConnecting = false
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isConnecting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
