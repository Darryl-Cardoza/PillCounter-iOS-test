//
//  ModelInputDump.swift
//  PillCounter
//
//  Debug-only sink for the exact 640×640 image handed to the pill model.
//

import CoreImage
import CoreVideo
import Foundation

/// Writes every `everyNFrames`th pill-model input as a JPEG named
/// `<frame>_<label>.jpg` under Documents/model_input, where the label says
/// whether the input was the tray crop (and its size in frame pixels) or the
/// full frame. Only the newest `keepFiles` files are kept. DEBUG builds only.
///
/// Retrieve them with Xcode → Window → Devices and Simulators → select the app →
/// Download Container, then open AppData/Documents/model_input.
enum ModelInputDump {

    private static let everyNFrames = 10
    private static let keepFiles = 30
    private static var frame = 0
    private static let context = CIContext()

    static let directory: URL? = {
        #if DEBUG
        return FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("model_input", isDirectory: true)
        #else
        return nil
        #endif
    }()

    static func maybeSave(_ buffer: CVPixelBuffer, label: String) {
        guard let dir = directory else { return }
        let index = frame
        frame += 1
        guard index % everyNFrames == 0 else { return }
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let image = CIImage(cvPixelBuffer: buffer)
            guard let data = context.jpegRepresentation(of: image,
                                                        colorSpace: CGColorSpaceCreateDeviceRGB(),
                                                        options: [:]) else { return }
            let name = String(format: "%06d_%@.jpg", index, label)
            try data.write(to: dir.appendingPathComponent(name))

            let files = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            if files.count > keepFiles {
                for f in files.prefix(files.count - keepFiles) { try? fm.removeItem(at: f) }
            }
        } catch {
            print("⚠️ [ModelInputDump] failed: \(error)")
        }
    }
}
