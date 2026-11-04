import SwiftUI
import AVKit
import ImageIO
import QuickLook

/// A swipeable viewer for items in the currently visible library.
struct VaultItemBrowser: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let items: [VaultItem]

    @State private var selectedID: UUID
    @State private var confirmExport = false
    @State private var exportedURL: URL?
    @State private var exportError: String?

    init(item: VaultItem, items: [VaultItem]) {
        self.items = items
        _selectedID = State(initialValue: item.id)
    }

    private var index: Int { items.firstIndex(where: { $0.id == selectedID }) ?? 0 }
    private var current: VaultItem? { items.indices.contains(index) ? items[index] : nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $selectedID) {
                    ForEach(items) { item in
                        VaultItemPage(item: item)
                            .tag(item.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 20) {
                    Button {
                        move(-1)
                    } label: {
                        Label("Previous", systemImage: "chevron.left")
                            .labelStyle(.iconOnly)
                            .frame(width: 48, height: 48)
                    }
                    .disabled(index == 0)

                    Spacer()

                    Text("\(items.isEmpty ? 0 : index + 1) of \(items.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        move(1)
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                            .labelStyle(.iconOnly)
                            .frame(width: 48, height: 48)
                    }
                    .disabled(index >= items.count - 1)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial)
            }
            .background(Color(red: 0.035, green: 0.05, blue: 0.075))
            .navigationTitle(current?.name ?? "Vault item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Export") { confirmExport = true }
                        .disabled(current == nil)
                }
            }
            .confirmationDialog("Export an unencrypted copy?", isPresented: $confirmExport) {
                Button("Export file") {
                    guard let current else { return }
                    do {
                        exportedURL = try model.store.decryptToProtectedTemporaryFile(current)
                    } catch {
                        exportError = error.localizedDescription
                    }
                }
            } message: {
                Text("The exported file is not protected by CipherVault encryption.")
            }
            .sheet(isPresented: Binding(
                get: { exportedURL != nil },
                set: { if !$0 { exportedURL = nil } }
            ), onDismiss: cleanupExport) {
                if let exportedURL {
                    ActivityShareView(items: [exportedURL])
                }
            }
            .alert("Export failed", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("OK") { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
            .onDisappear(perform: cleanupExport)
        }
        .preferredColorScheme(.dark)
    }

    private func move(_ distance: Int) {
        let target = index + distance
        guard items.indices.contains(target) else { return }
        withAnimation { selectedID = items[target].id }
    }

    private func cleanupExport() {
        if let exportedURL { model.store.removeTemporaryFile(exportedURL) }
        exportedURL = nil
    }
}

/// One decrypted preview at a time. Sensitive memory and temporary files are
/// discarded as pages disappear or whenever the vault locks.
private struct VaultItemPage: View {
    @EnvironmentObject private var model: AppModel
    let item: VaultItem

    @State private var image: UIImage?
    @State private var note: String?
    @State private var player: AVPlayer?
    @State private var videoURL: URL?
    @State private var quickLookURL: URL?
    @State private var errorText: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let errorText {
                ContentUnavailableView(errorText, systemImage: "exclamationmark.triangle")
            } else if item.kind == .photo, let image {
                ScrollView {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            } else if item.kind == .video, let player {
                VideoPlayer(player: player)
            } else if item.kind == .note, let note {
                ScrollView {
                    Text(note)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(22)
                }
            } else if item.kind == .file {
                VStack(spacing: 20) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 58))
                        .foregroundStyle(.cyan)
                    Text(item.name).font(.headline).multilineTextAlignment(.center)
                    Text(ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file))
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        do {
                            quickLookURL = try model.store.decryptToProtectedTemporaryFile(item)
                        } catch {
                            errorText = error.localizedDescription
                        }
                    } label: {
                        Label("Preview file", systemImage: "eye")
                    }
                    .buttonStyle(.borderedProminent)
                    Text("Swipe to see the next item in your library.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
            } else if isLoading {
                ProgressView("Opening securely…")
            } else {
                ContentUnavailableView("Preview unavailable", systemImage: item.kind.icon)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .quickLookPreview($quickLookURL)
        .onChange(of: quickLookURL) { oldValue, newValue in
            if newValue == nil, let oldValue {
                model.store.removeTemporaryFile(oldValue)
            }
        }
        .task(id: item.id) { await load() }
        .onDisappear(perform: cleanup)
    }

    private func load() async {
        guard model.route == .vault else { return }
        guard item.kind != .file else {
            isLoading = false
            return
        }
        isLoading = true
        do {
            let url = try await model.store.preparePreview(for: item)
            guard !Task.isCancelled, model.route == .vault else {
                model.store.removeTemporaryFile(url)
                return
            }

            switch item.kind {
            case .photo:
                let newImage = await Task.detached(priority: .utility) {
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                        return Optional<UIImage>.none
                    }
                    let options: [CFString: Any] = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 2800,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceShouldCache: false
                    ]
                    guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                        return Optional<UIImage>.none
                    }
                    return UIImage(cgImage: cg)
                }.value
                model.store.removeTemporaryFile(url)
                guard !Task.isCancelled, model.route == .vault else { return }
                image = newImage

            case .video:
                videoURL = url
                player = AVPlayer(url: url)

            case .note:
                let bytes = try Data(contentsOf: url)
                model.store.removeTemporaryFile(url)
                guard !Task.isCancelled, model.route == .vault else { return }
                note = String(decoding: bytes, as: UTF8.self)

            case .file:
                model.store.removeTemporaryFile(url)
            }
        } catch {
            guard !Task.isCancelled, model.route == .vault else { return }
            errorText = error.localizedDescription
        }
        isLoading = false
    }

    private func cleanup() {
        player?.pause()
        player = nil
        image = nil
        note = nil
        isLoading = true
        if let videoURL { model.store.removeTemporaryFile(videoURL) }
        videoURL = nil
        if let quickLookURL { model.store.removeTemporaryFile(quickLookURL) }
        quickLookURL = nil
    }
}
