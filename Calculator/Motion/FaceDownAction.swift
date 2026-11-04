import Foundation
import UIKit

/// An optional destination after the vault has been locked by a face-down gesture.
/// Apple decides whether a link opens an installed app, a browser, or cannot open.
enum FaceDownAction: String, CaseIterable, Identifiable {
    case calculator
    case youtube
    case gmail
    case browser
    case customWebsite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calculator: return "Return to calculator"
        case .youtube: return "Open YouTube"
        case .gmail: return "Open Gmail"
        case .browser: return "Open browser"
        case .customWebsite: return "Open custom website"
        }
    }

    /// Validate the user's URL before offering it to iOS. No custom schemes
    /// (such as javascript:, file:, or arbitrary app schemes) are accepted.
    static func safeWebsite(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let components = URLComponents(string: normalized),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              !host.contains(" "),
              let url = components.url else { return nil }
        return url
    }

    /// Call only from the foreground, after the encrypted vault has been locked.
    @MainActor
    func openDestination(customWebsite: String) {
        let first: URL?
        let fallback: URL?

        switch self {
        case .calculator:
            return
        case .youtube:
            first = URL(string: "youtube://")
            fallback = URL(string: "https://www.youtube.com/")
        case .gmail:
            first = URL(string: "googlegmail://")
            fallback = URL(string: "https://mail.google.com/")
        case .browser:
            first = URL(string: "https://www.google.com/")
            fallback = nil
        case .customWebsite:
            first = Self.safeWebsite(customWebsite)
            fallback = nil
        }

        guard let first else { return }
        UIApplication.shared.open(first, options: [:]) { opened in
            guard !opened, let fallback else { return }
            UIApplication.shared.open(fallback, options: [:], completionHandler: nil)
        }
    }
}
