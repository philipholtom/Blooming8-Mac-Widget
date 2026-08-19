import Foundation
import CryptoKit

/// A named group of galleries, optionally gated behind a password. This is a
/// UI-level deterrent only — the frame's HTTP API has no auth of its own, so
/// anyone on the LAN can still bypass it with a direct request. It just keeps
/// someone casually clicking through the menu bar (a kid, a houseguest) out
/// of galleries you've grouped away.
public struct GalleryTab: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var galleryNames: Set<String>
    public var passwordHash: String?

    public init(id: UUID = UUID(), name: String, galleryNames: Set<String> = [], passwordHash: String? = nil) {
        self.id = id
        self.name = name
        self.galleryNames = galleryNames
        self.passwordHash = passwordHash
    }

    public var isLocked: Bool { passwordHash != nil }
}

public enum PasswordHasher {
    public static func hash(_ password: String) -> String {
        SHA256.hash(data: Data(password.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
