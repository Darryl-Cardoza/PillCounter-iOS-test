//
//  HL7Message+Segments.swift
//  PillCounter
//

import Hl7Core

/// Typed-segment convenience accessors on top of `HL7Message.segmentNamed(name:)` /
/// `.segmentsNamed(name:)`, so call sites don't repeat the `as? XSegment` cast.
///
/// `segment(name:)` / `segments(name:)` are bridged from a Kotlin *reified inline*
/// generic (`message.segment<RXDSegment>("RXD")`) — reified generics don't exist in
/// the Objective-C runtime, so calling them through the Swift bridge crashes with
/// `kotlin.IllegalStateException: unsupported call of reified inlined function`.
/// `segmentNamed(name:)` / `segmentsNamed(name:)` are the actual non-generic,
/// ObjC-safe equivalents — always use those from Swift.
extension HL7Message {

    /// RXE — Pharmacy/Treatment Encoded Order. A dispense/order request can carry
    /// multiple medications, one RXE segment each.
    var medications: [RXESegment] {
        segmentsNamed(name: "RXE").compactMap { $0 as? RXESegment }
    }

    /// ORC — Common Order. One per message.
    var order: ORCSegment? {
        segmentNamed(name: "ORC") as? ORCSegment
    }

    /// ZIN — custom inventory segment (per-container opened/sealed quantity, lot, expiry).
    var zinSegments: [ZINSegment] {
        segmentsNamed(name: "ZIN").compactMap { $0 as? ZINSegment }
    }

    /// ZPR — custom Rx priority segment. One per message.
    var priority: ZPRSegment? {
        segmentNamed(name: "ZPR") as? ZPRSegment
    }

    /// ZUI — Vivid order-data-packet segment (RDE^O11, PMSS → Vivid). One per message.
    var zuiOrder: ZUISegment? {
        segmentNamed(name: "ZUI") as? ZUISegment
    }

    /// ZNI — Eyecon-to-Computer dispense result segment. One per message.
    var zniSegment: ZNISegment? {
        segmentNamed(name: "ZNI") as? ZNISegment
    }
}
