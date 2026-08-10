//
//  ZipArchiveWriter.swift
//  PillCounter
//

import Foundation

/// Builds an in-memory ZIP archive (uncompressed / STORE entries only).
/// No third-party dependency: this is the plain ZIP32 container format —
/// local file header + raw bytes per entry, followed by the central directory.
/// STORE (no deflate) is used because entries here are JPEGs, which barely
/// shrink further under deflate, and STORE keeps this writer trivially correct.
struct ZipArchiveWriter {

    private struct Entry {
        let name: String
        let data: Data
        let crc32: UInt32
        let offset: UInt32
    }

    private var entries: [Entry] = []
    private var body = Data()

    /// Appends a file to the archive.
    mutating func addEntry(name: String, data: Data) {
        let offset = UInt32(body.count)
        let crc = Self.crc32(data)

        var localHeader = Data()
        localHeader.appendLE(UInt32(0x04034b50))          // local file header signature
        localHeader.appendLE(UInt16(20))                  // version needed to extract
        localHeader.appendLE(UInt16(0))                   // flags
        localHeader.appendLE(UInt16(0))                   // compression method: STORE
        localHeader.appendLE(UInt16(0))                   // mod time
        localHeader.appendLE(UInt16(0))                   // mod date
        localHeader.appendLE(crc)                         // crc-32
        localHeader.appendLE(UInt32(data.count))           // compressed size
        localHeader.appendLE(UInt32(data.count))           // uncompressed size
        let nameData = Data(name.utf8)
        localHeader.appendLE(UInt16(nameData.count))       // file name length
        localHeader.appendLE(UInt16(0))                   // extra field length
        localHeader.append(nameData)

        body.append(localHeader)
        body.append(data)

        entries.append(Entry(name: name, data: data, crc32: crc, offset: offset))
    }

    /// Finalizes the archive (appends central directory) and returns the full ZIP bytes.
    func finalize() -> Data {
        var centralDirectory = Data()

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            var record = Data()
            record.appendLE(UInt32(0x02014b50))            // central directory header signature
            record.appendLE(UInt16(20))                    // version made by
            record.appendLE(UInt16(20))                    // version needed to extract
            record.appendLE(UInt16(0))                     // flags
            record.appendLE(UInt16(0))                     // compression method: STORE
            record.appendLE(UInt16(0))                     // mod time
            record.appendLE(UInt16(0))                     // mod date
            record.appendLE(entry.crc32)                   // crc-32
            record.appendLE(UInt32(entry.data.count))      // compressed size
            record.appendLE(UInt32(entry.data.count))      // uncompressed size
            record.appendLE(UInt16(nameData.count))        // file name length
            record.appendLE(UInt16(0))                     // extra field length
            record.appendLE(UInt16(0))                     // file comment length
            record.appendLE(UInt16(0))                     // disk number start
            record.appendLE(UInt16(0))                     // internal file attributes
            record.appendLE(UInt32(0))                     // external file attributes
            record.appendLE(entry.offset)                  // relative offset of local header
            record.append(nameData)
            centralDirectory.append(record)
        }

        var end = Data()
        end.appendLE(UInt32(0x06054b50))                   // end of central directory signature
        end.appendLE(UInt16(0))                            // disk number
        end.appendLE(UInt16(0))                            // disk with central directory
        end.appendLE(UInt16(entries.count))                // entries on this disk
        end.appendLE(UInt16(entries.count))                // total entries
        end.appendLE(UInt32(centralDirectory.count))       // size of central directory
        end.appendLE(UInt32(body.count))                   // offset of central directory
        end.appendLE(UInt16(0))                            // comment length

        var archive = body
        archive.append(centralDirectory)
        archive.append(end)
        return archive
    }

    // MARK: - CRC-32 (standard zlib/ZIP polynomial)

    private static let crcTable: [UInt32] = {
        (0...255).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1 != 0) ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = crcTable[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendLE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
