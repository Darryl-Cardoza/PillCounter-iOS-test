//
//  FaceAvatarStore.swift
//  PillCounter
//
//  File-backed store for enrolled users' avatar thumbnails — the frontal frame
//  captured during face enrollment, rendered in the Quick Access Users row.
//
//  The JPEG bytes live on disk rather than in Core Data: a 256×256 thumbnail is
//  a poor fit for a managed-object attribute (it bloats every FaceUserEntity
//  fetch, including the per-frame authentication path that only wants
//  embeddings). Core Data holds only the filename, and that field IS encrypted
//  (see encryptedFieldRegistry in NSManagedObject+Encryption).
//
//  Location is Application Support, NOT Documents: these are app-managed files
//  the user never browses, and Documents is user-visible on a file-sharing
//  build. Either way the directory is inside the app container, so uninstalling
//  the app destroys every avatar with it — no image outlives the enrollment
//  that produced it.
//

import UIKit

final class FaceAvatarStore {

    static let shared = FaceAvatarStore()

    private let fileManager: FileManager

    /// JPEG compression for the stored thumbnail. This image is only ever
    /// displayed at 64×64 — quality beyond this is bytes nobody sees.
    private let jpegQuality: CGFloat = 0.8

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Location

    private var directoryURL: URL? {
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            Log("FaceAvatarStore: no Application Support directory")
            return nil
        }
        return base.appendingPathComponent("FaceAvatars", isDirectory: true)
    }

    /// Creates the avatar directory on first use and marks it
    /// backup-excluded — an avatar restored onto a different device would
    /// point at embeddings that device's Keychain key cannot open, so there is
    /// nothing to gain by backing the images up.
    private func ensureDirectory() -> URL? {
        guard let directoryURL else { return nil }
        if fileManager.fileExists(atPath: directoryURL.path) { return directoryURL }

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                // Readable once the device has been unlocked at least since
                // boot. `.complete` would fail the row render whenever the
                // list is rebuilt while locked (e.g. a background refresh).
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            var mutableURL = directoryURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try mutableURL.setResourceValues(values)
            return directoryURL
        } catch {
            Log("FaceAvatarStore: failed to create avatar directory — \(error.localizedDescription)")
            return nil
        }
    }

    /// Resolves a stored filename to an absolute URL. Only the filename is
    /// persisted, never an absolute path: the container path changes across
    /// reinstall and device restore, which would strand every stored path.
    private func url(for filename: String) -> URL? {
        guard !filename.isEmpty else { return nil }
        // Defends against a filename that has picked up path components
        // (from a legacy row, or a full path stored by mistake) escaping the
        // avatar directory.
        let sanitized = (filename as NSString).lastPathComponent
        guard !sanitized.isEmpty else { return nil }
        return directoryURL?.appendingPathComponent(sanitized, isDirectory: false)
    }

    // MARK: - Write

    /// Writes `image` as this user's avatar and returns the filename to persist
    /// on the user row, or nil if the write failed. Callers treat nil as "no
    /// avatar" — never as an enrollment failure.
    @discardableResult
    func save(userId: String, image: UIImage) -> String? {
        guard !userId.isEmpty else { return nil }
        guard let directoryURL = ensureDirectory() else { return nil }
        guard let data = image.jpegData(compressionQuality: jpegQuality) else {
            Log("FaceAvatarStore: JPEG encoding failed for user \(userId)")
            return nil
        }

        let filename = "\(userId).jpg"
        let fileURL = directoryURL.appendingPathComponent(filename, isDirectory: false)
        do {
            try data.write(to: fileURL, options: .atomic)
            // `.atomic` writes via a temporary file and moves it into place, so
            // the destination does not inherit the directory's protection
            // class — set it on the file explicitly.
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: fileURL.path
            )
            return filename
        } catch {
            Log("FaceAvatarStore: failed to write avatar for user \(userId) — \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Read

    /// Loads the avatar for a stored filename. Returns nil when the row has no
    /// avatar, the file is missing (enrolled before avatars existed, or removed
    /// out from under us), or the bytes are unreadable — every caller falls
    /// back to a placeholder rather than treating this as an error.
    func loadImage(filename: String?) -> UIImage? {
        guard let filename, let fileURL = url(for: filename) else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Delete

    func delete(filename: String?) {
        guard let filename, let fileURL = url(for: filename) else { return }
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            Log("FaceAvatarStore: failed to delete avatar \(filename) — \(error.localizedDescription)")
        }
    }

    /// Removes every stored avatar. Paired with `FaceUserStore.deleteAll` — the
    /// user rows and their images must never outlive each other.
    func deleteAll() {
        guard let directoryURL, fileManager.fileExists(atPath: directoryURL.path) else { return }
        do {
            try fileManager.removeItem(at: directoryURL)
        } catch {
            Log("FaceAvatarStore: failed to delete avatar directory — \(error.localizedDescription)")
        }
    }
}
