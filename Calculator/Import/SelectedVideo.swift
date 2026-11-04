import Foundation
import CoreTransferable
import UniformTypeIdentifiers

struct SelectedVideo: Transferable {
    let temporaryURL: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let filename = UUID().uuidString + "." +
                (received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try FileManager.default.copyItem(at: received.file, to: destination)
            try (destination as NSURL).setResourceValue(FileProtectionType.complete, forKey: .fileProtectionKey)
            return SelectedVideo(temporaryURL: destination)
        }
    }
}
