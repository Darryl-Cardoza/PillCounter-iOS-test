//
//  FaceAvatarStoreTests.swift
//  PillCounterTests
//
//  Covers the on-disk half of the Quick Access avatar feature: round-tripping a
//  thumbnail, the placeholder-triggering nil paths, and cleanup.
//
//  These tests share the real Application Support directory (FaceAvatarStore
//  resolves it from the process), so each test writes under its own user id and
//  removes it afterwards rather than calling `deleteAll()` — see the note on
//  `deleteAllRemovesEveryAvatar`.
//

import Testing
import UIKit
@testable import PillCounter

struct FaceAvatarStoreTests {

    private let store = FaceAvatarStore()

    /// Distinct per test so tests sharing the avatar directory cannot collide.
    private func userId(_ suffix: String) -> String {
        "test-avatar-\(suffix)-\(UUID().uuidString)"
    }

    private func makeImage(size: CGFloat = 32, color: UIColor = .red) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        }
    }

    @Test func saveThenLoadRoundTripsTheImage() {
        let id = userId("roundtrip")
        defer { store.delete(filename: "\(id).jpg") }

        let filename = store.save(userId: id, image: makeImage())

        #expect(filename == "\(id).jpg")
        let loaded = store.loadImage(filename: filename)
        #expect(loaded != nil)
        // JPEG is lossy, so the bytes differ — the dimensions must not.
        #expect(loaded?.size == CGSize(width: 32, height: 32))
    }

    @Test func saveRejectsAnEmptyUserId() {
        #expect(store.save(userId: "", image: makeImage()) == nil)
    }

    @Test func loadReturnsNilForNilFilename() {
        #expect(store.loadImage(filename: nil) == nil)
    }

    @Test func loadReturnsNilForEmptyFilename() {
        // What a failed field decrypt leaves behind (see
        // decryptEncryptedFieldsInPlace) — must read as "no avatar", never as a
        // lookup of the avatar directory itself.
        #expect(store.loadImage(filename: "") == nil)
    }

    @Test func loadReturnsNilForMissingFile() {
        // A user enrolled before avatars existed, or whose file was removed.
        #expect(store.loadImage(filename: "\(userId("missing")).jpg") == nil)
    }

    @Test func deleteRemovesTheStoredAvatar() {
        let id = userId("delete")
        let filename = store.save(userId: id, image: makeImage())
        #expect(store.loadImage(filename: filename) != nil)

        store.delete(filename: filename)

        #expect(store.loadImage(filename: filename) == nil)
    }

    @Test func deleteOfMissingFileIsSilent() {
        // Deleting a user with no avatar must not be an error path.
        store.delete(filename: "\(userId("absent")).jpg")
        store.delete(filename: nil)
    }

    @Test func pathComponentsInFilenameCannotEscapeTheDirectory() {
        // A stored absolute path (from a legacy row or a mistake) must resolve
        // to its last component inside the avatar directory, not to the path
        // itself, so a lookup can never reach outside.
        let id = userId("sanitize")
        let filename = store.save(userId: id, image: makeImage())
        defer { store.delete(filename: filename) }

        #expect(store.loadImage(filename: "/etc/\(id).jpg") != nil)
        #expect(store.loadImage(filename: "../../\(id).jpg") != nil)
    }

    @Test func deleteAllRemovesEveryAvatar() {
        // Runs last-ish by name and intentionally clears the shared directory:
        // this mirrors the keychain-wipe path (AppStorage.deleteAll), which is
        // all-or-nothing by design. Re-saving afterwards proves the directory
        // is recreated on next use rather than left broken.
        let id = userId("deleteall")
        let filename = store.save(userId: id, image: makeImage())
        #expect(store.loadImage(filename: filename) != nil)

        store.deleteAll()

        #expect(store.loadImage(filename: filename) == nil)

        let recreated = store.save(userId: id, image: makeImage())
        #expect(recreated != nil)
        store.delete(filename: recreated)
    }
}
