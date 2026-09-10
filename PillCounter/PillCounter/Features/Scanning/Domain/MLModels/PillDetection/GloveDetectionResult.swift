// GloveDetectionResult.swift
// PillCounter
//
// Shared result types for the three-model detection pipeline:
//   1. pills_detector_fp16  — PP-YOLOE+s pill detector
//   2. tray_detector_fp16   — RTMDet-Tiny tray/chute detector
//   3. gloves_detector_fp32 — YOLOX-Nano glove safety detector
//
// This file defines the class enums and result structs for tray and glove
// detections. DetectionResult (pills) remains in PillDetectionService.swift.

import Foundation
import CoreGraphics

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Tray Classification
// ─────────────────────────────────────────────────────────────────────────────

/// The two object classes output by the RTMDet-Tiny tray model.
///
/// The model (tray_detector_fp16.mlpackage) was trained on two region types:
///   • Class index 0 → TRAY   : the counting tray where pills are placed
///   • Class index 1 → CHUTE  : the chute / dispenser opening
///
/// Pills are only counted inside TRAY regions; CHUTE regions are displayed
/// with a distinct colour overlay so the operator can orient the device.
enum TrayClass {
    case tray   // Class 0 — the counting tray (main region of interest)
    case chute  // Class 1 — the chute / dispenser region
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Glove Classification
// ─────────────────────────────────────────────────────────────────────────────

/// The two object classes output by the YOLOX-Nano glove model.
///
/// The model (gloves_detector_fp32.mlpackage) was trained to detect:
///   • Class index 0 → GLOVE    : operator is wearing protective gloves (safe)
///   • Class index 1 → NO_GLOVE : bare hands visible (hazardous — pause count)
///
/// The UI shows a warning banner when isHazardous is true and can optionally
/// pause pill counting until gloves are detected.
enum GloveClass: Equatable {
    case glove      // Safe — gloves detected
    case noGlove    // Hazardous — bare hands visible, warn the operator
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Glove Detection Result
// ─────────────────────────────────────────────────────────────────────────────

/// A single detection returned by GloveDetectionService.
///
/// rect is in the original (un-letterboxed) camera-frame coordinate space,
/// exactly as DetectionResult and TrayResult carry their coordinates. The
/// CameraService overlays use originalFrameSize to normalise before passing
/// through AVCaptureVideoPreviewLayer.layerRectConverted.
struct GloveDetectionResult: Identifiable {
    let id = UUID()

    /// Bounding box in original camera-frame pixel coordinates (pre-letterbox).
    let rect: CGRect

    /// Final detection confidence: sigmoid(obj) × sigmoid(cls), range 0–1.
    let confidence: Float

    /// The pixel dimensions of the raw camera frame this result was generated from.
    let originalFrameSize: CGSize

    /// Whether gloves (0) or bare hands (1) were detected at this location.
    let gloveClass: GloveClass

    /// True when bare hands are detected at this location.
    /// Drives the warning overlay and optionally pauses pill counting.
    var isHazardous: Bool { gloveClass == .noGlove }
}
