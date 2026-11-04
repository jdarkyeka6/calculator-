import SwiftUI
import ImageIO

/// Navigation-only presentation. VaultStore is still the single encrypted source
/// of truth and is emptied whenever the app locks.
enum LibrarySection: String, CaseIterable, Identifiable {
    case all, photo, video, file, note
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .photo: return "Photos"
        case .video: return "Videos"
        case .file: return "Files"
        case .note: return "Notes"
        }
    }
    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .photo: return "photo.on.rectangle"
        case .video: return "play.rectangle"
        case .file: return "doc"
        case .note: return "note.text"
        }
    }
    var kind: VaultKind? { self == .all ? nil : VaultKind(rawValue: rawValue) }
}

struct VaultLibraryView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selectedItem: VaultItem?
    @State private var section: LibrarySection = .all
    @State private var searchText = ""
    @State private var pendingDelete: VaultItem?

    private let columns = [GridItem(.flexible(), spacing: 3),
                           GridItem(.flexible(), spacing: 3),
                           GridItem(.flexible(), spacing: 3)]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(LibrarySection.allCases) { tab in
                        Button {
                            section = tab
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: tab.icon)
                                Text(tab.title)
                                Text("\(count(for: tab))")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(section == tab ? Color.black.opacity(0.65) : .secondary)
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .foregroundStyle(section == tab ? Color.black : Color.primary)
                            .background(section == tab ? Color.cyan : Color.white.opacity(0.08),
                                        in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(tab.title), \(count(for: tab)) items")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            if visibleItems.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No \(section.title.lowercased()) yet" : "Nothing found",
                    systemImage: section.icon,
                    description: Text(searchText.isEmpty
                                      ? "Tap + to add photos, videos, documents or notes."
                                      : "Try a different filename or category."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(section == .all ? "Your Library" : section.title)
                                .font(.title2.bold())
                            Spacer()
                            Text("\(visibleItems.count) items")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 8)

                        if section == .photo || section == .video {
                            LazyVGrid(columns: columns, spacing: 3) {
                                ForEach(visibleItems) { item in
                                    Button { selectedItem = item } label: {
                                        ZStack(alignment: .bottomTrailing) {
                                            if item.kind == .photo {
                                                VaultPhotoThumbnail(item: item, size: 145)
                                            } else {
                                                Rectangle()
                                                    .fill(.white.opacity(0.08))
                                                    .overlay {
                                                        Image(systemName: "play.rectangle.fill")
                                                            .font(.system(size: 32))
                                                            .foregroundStyle(.cyan)
                                                    }
                                            }
                                            if item.kind == .video {
                                                Image(systemName: "play.fill")
                                                    .font(.footnote)
                                                    .padding(7)
                                                    .background(.black.opacity(0.5), in: Circle())
                                                    .padding(6)
                                            }
                                        }
                                        .aspectRatio(1, contentMode: .fit)
                                        .clipped()
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button("Delete", systemImage: "trash", role: .destructive) {
                                            pendingDelete = item
                                        }
                                    }
                                    .accessibilityLabel(item.name)
                                }
                            }
                        } else {
                            LazyVStack(spacing: 6) {
                                ForEach(visibleItems) { item in
                                    Button { selectedItem = item } label: {
                                        HStack(spacing: 13) {
                                            if item.kind == .photo {
                                                VaultPhotoThumbnail(item: item, size: 62)
                                                    .frame(width: 62, height: 62)
                                                    .clipShape(RoundedRectangle(cornerRadius: 11))
                                            } else {
                                                RoundedRectangle(cornerRadius: 11)
                                                    .fill(Color.cyan.opacity(0.11))
                                                    .frame(width: 62, height: 62)
                                                    .overlay {
                                                        Image(systemName: item.kind.icon)
                                                            .font(.title2)
                                                            .foregroundStyle(.cyan)
                                                    }
                                            }
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text(item.name).font(.subheadline.weight(.medium))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(2)
                                                Text("\(item.kind.rawValue.capitalized) • \(ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file))")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer(minLength: 3)
                                            Image(systemName: "chevron.right")
                                                .foregroundStyle(.tertiary)
                                        }
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 16)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button("Delete", systemImage: "trash", role: .destructive) {
                                            pendingDelete = item
                                        }
                                    }
                                    Divider().padding(.leading, 90)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search your private library")
        .confirmationDialog("Delete \(pendingDelete?.name ?? "item")?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete permanently", role: .destructive) {
                if let item = pendingDelete {
                    do { try model.store.delete(item) }
                    catch { model.errorMessage = error.localizedDescription }
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This removes the encrypted copy from CipherVault. It cannot be undone.")
        }
    }

    private func count(for tab: LibrarySection) -> Int {
        model.store.items.filter { tab.kind == nil || $0.kind == tab.kind }.count
    }

    private var visibleItems: [VaultItem] {
        model.store.items
            .filter { section.kind == nil || $0.kind == section.kind }
            .filter {
                searchText.isEmpty ||
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.source.localizedCaseInsensitiveContains(searchText)
            }
            .sorted {
                if $0.importedAt == $1.importedAt { return $0.name < $1.name }
                return $0.importedAt > $1.importedAt
            }
    }
}

/// Makes a small image in RAM from a temporary file-protected decrypt.
/// No unencrypted thumbnail is persisted as a separate library cache.
struct VaultPhotoThumbnail: View {
    @EnvironmentObject private var model: AppModel
    let item: VaultItem
    let size: CGFloat
    @State private var thumbnail: UIImage?

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.cyan.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fill)
            .clipped()
            .task(id: item.id) {
                guard item.kind == .photo else { return }
                let url: URL
                do {
                    url = try await model.store.preparePreview(for: item)
                } catch {
                    return
                }
                let pixels = Int(max(128, size * 2))
                let image = await Task.detached(priority: .utility) {
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                        return Optional<UIImage>.none
                    }
                    let options: [CFString: Any] = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: pixels,
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
                thumbnail = image
            }
            .onDisappear { thumbnail = nil }
    }
}
