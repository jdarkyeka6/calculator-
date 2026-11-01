import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVKit

struct VaultHomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var filter: VaultKind?
    @State private var importFiles = false
    @State private var showNote = false
    @State private var showSecurity = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var selectedItem: VaultItem?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "lock.shield.fill").font(.largeTitle).foregroundStyle(.cyan)
                        VStack(alignment: .leading) {
                            Text("Encrypted on this iPhone").font(.headline)
                            Text("\(model.store.items.count) private items • Offline storage")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8)
                }

                Section("Import") {
                    Button { importFiles = true } label: {
                        Label("Files or ZIP of photos", systemImage: "folder.badge.plus")
                    }
                    .disabled(model.isImporting)
                    Text("Select a ZIP to import all supported photos. Non-photo entries are skipped.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if model.isImporting {
                        ProgressView(model.importStatus ?? "Importing…")
                    } else if let status = model.importStatus {
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                    PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 0,
                                 matching: .any(of: [.images, .videos]),
                                 preferredItemEncoding: .current) {
                        Label("Photos and videos", systemImage: "photo.on.rectangle.angled")
                    }
                    .disabled(model.isImporting)
                    Button { showNote = true } label: {
                        Label("Write encrypted note", systemImage: "square.and.pencil")
                    }
                }

                Section {
                    Picker("Filter", selection: $filter) {
                        Text("All").tag(nil as VaultKind?)
                        ForEach(VaultKind.allCases) { kind in
                            Text(kind.rawValue.capitalized).tag(Optional(kind))
                        }
                    }
                    .pickerStyle(.segmented)
                    if filtered.isEmpty {
                        ContentUnavailableView("No items yet", systemImage: "lock.doc",
                                               description: Text("Import a file or write a note to begin."))
                    }
                    ForEach(filtered) { item in
                        Button { selectedItem = item } label: {
                            HStack {
                                Image(systemName: item.kind.icon)
                                    .frame(width: 34).foregroundStyle(.cyan)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name).foregroundStyle(.primary)
                                    Text("\(ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file)) • \(item.kind.rawValue)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .onDelete(perform: delete)
                } header: { Text("Vault") }
                footer: {
                    Text("Duplicates are skipped. Importing keeps your vault open; Lock, face-down and backgrounding still lock it.")
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("CipherVault")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSecurity = true } label: { Image(systemName: "shield.lefthalf.filled") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Lock", systemImage: "lock.fill") { model.emergencyCover() }
                }
            }
            .fileImporter(isPresented: $importFiles, allowedContentTypes: [.item],
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): Task { await model.importFiles(urls) }
                case .failure(let error): model.errorMessage = error.localizedDescription
                }
            }
            .onChange(of: selectedPhotos) { _, choices in
                guard !choices.isEmpty else { return }
                Task {
                    await importPhotoSelections(choices)
                    selectedPhotos = []
                }
            }
            .sheet(isPresented: $showNote) { NewNoteView() }
            .sheet(isPresented: $showSecurity) { SecurityView() }
            .sheet(item: $selectedItem) { item in VaultItemDetail(item: item) }
        }
    }

    private var filtered: [VaultItem] {
        model.store.items.filter { filter == nil || $0.kind == filter }
    }

    private func delete(at offsets: IndexSet) {
        for offset in offsets {
            do { try model.store.delete(filtered[offset]) }
            catch { model.errorMessage = error.localizedDescription }
        }
    }

    @MainActor
    private func importPhotoSelections(_ choices: [PhotosPickerItem]) async {
        guard model.route == .vault, !model.isImporting else { return }
        model.isImporting = true
        model.imported = 0
        model.skipped = 0
        model.importFailed = 0
        defer {
            model.isImporting = false
            if model.route == .vault {
                model.importStatus = "Import complete: \(model.imported) added, \(model.skipped) duplicates, \(model.importFailed) failed."
            }
        }
        for (index, choice) in choices.enumerated() {
            guard model.route == .vault else { break }
            model.importStatus = "Importing photo or video \(index + 1) of \(choices.count)…"
            let isVideo = choice.supportedContentTypes.contains { $0.conforms(to: .movie) }
            do {
                if isVideo {
                    guard let video = try await choice.loadTransferable(type: SelectedVideo.self) else {
                        throw VaultError.missingFile
                    }
                    defer { try? FileManager.default.removeItem(at: video.temporaryURL) }
                    let added = try await model.store.importFile(video.temporaryURL, kind: .video,
                            name: "Imported video \(index + 1).\(video.temporaryURL.pathExtension)",
                            sourceName: "Photos")
                    if added { model.imported += 1 } else { model.skipped += 1 }
                } else {
                    guard let data = try await choice.loadTransferable(type: Data.self) else {
                        throw VaultError.missingFile
                    }
                    let ext = choice.supportedContentTypes.first(where: { $0.conforms(to: .image) })?
                        .preferredFilenameExtension ?? "heic"
                    let temporary = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
                    try data.write(to: temporary, options: [.atomic, .completeFileProtection])
                    defer { try? FileManager.default.removeItem(at: temporary) }
                    let added = try await model.store.importFile(temporary, kind: .photo,
                            name: "Imported photo \(index + 1).\(ext)", sourceName: "Photos")
                    if added { model.imported += 1 } else { model.skipped += 1 }
                }
            } catch {
                if model.route != .vault { break }
                model.importFailed += 1
                model.errorMessage = "Photo import failed: \(error.localizedDescription)"
            }
        }
    }
}

struct NewNoteView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var content = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextEditor(text: $content).frame(minHeight: 250)
            }
            .navigationTitle("New Private Note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Encrypt") {
                        saving = true
                        Task {
                            do {
                                try await model.store.createNote(title: title, content: content)
                                dismiss()
                            } catch {
                                model.errorMessage = error.localizedDescription
                            }
                            saving = false
                        }
                    }
                    .disabled(saving || content.isEmpty)
                }
            }
        }.preferredColorScheme(.dark)
    }
}

struct VaultItemDetail: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let item: VaultItem
    @State private var data: Data?
    @State private var videoURL: URL?
    @State private var errorText: String?
    @State private var confirmExport = false
    @State private var exportedURL: URL?
    @State private var pendingCleanupURL: URL?

    var body: some View {
        NavigationStack {
            Group {
                if let errorText {
                    ContentUnavailableView(errorText, systemImage: "exclamationmark.triangle")
                } else if item.kind == .video, let videoURL {
                    VideoPlayer(player: AVPlayer(url: videoURL))
                } else if item.kind == .photo, let data, let image = UIImage(data: data) {
                    ScrollView {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxWidth: .infinity)
                    }
                } else if item.kind == .note, let data {
                    ScrollView {
                        Text(String(decoding: data, as: UTF8.self))
                            .frame(maxWidth: .infinity, alignment: .leading).padding()
                    }
                } else if item.kind == .file {
                    VStack(spacing: 15) {
                        Image(systemName: "doc.fill").font(.system(size: 56)).foregroundStyle(.cyan)
                        Text(item.name)
                        Text("Use Export to save a decrypted copy outside CipherVault.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }.padding()
                } else {
                    ProgressView("Decrypting…")
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Export") { confirmExport = true }
                }
            }
            .confirmationDialog("Export an unencrypted copy?", isPresented: $confirmExport) {
                Button("Export file") {
                    do {
                        let url = try model.store.decryptToProtectedTemporaryFile(item)
                        // Export uses iOS share sheet; recipients control the unencrypted copy.
                        pendingCleanupURL = url
                        exportedURL = url
                    } catch { errorText = error.localizedDescription }
                }
            } message: {
                Text("Exported files are no longer protected by CipherVault encryption.")
            }
            .sheet(isPresented: Binding(
                get: { exportedURL != nil },
                set: { if !$0 { exportedURL = nil } }
            ), onDismiss: {
                if let url = pendingCleanupURL { model.store.removeTemporaryFile(url) }
                pendingCleanupURL = nil
            }) {
                if let url = exportedURL { ActivityShareView(items: [url]) }
            }
            .task { await load() }
            .onDisappear {
                if let videoURL { model.store.removeTemporaryFile(videoURL) }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func load() async {
        do {
            if item.kind == .video {
                videoURL = try await model.store.preparePreview(for: item)
            } else if item.kind == .note || item.kind == .photo {
                data = try model.store.plaintext(for: item)
            }
        } catch { errorText = error.localizedDescription }
    }

}

struct ActivityShareView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
