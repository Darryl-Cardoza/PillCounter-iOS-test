//
//  OperatorName.swift
//  PillCounter
//

import Foundation

/// The operator identification shown on captured-image overlays and sent as the
/// HL7 inventory response's OPERATOR_NAME OBX. Whoever last authenticated via face
/// scan (the physical operator right now) takes priority; falls back to the
/// logged-in account's name (fname + lname) when no face session is active.
enum OperatorName {
    static func current(fname: String?, lname: String?) -> String {
        let accountName = [fname, lname]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let faceSessionName = AppStorageManager.shared.faceLockCurrentUserName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (faceSessionName?.isEmpty == false) ? faceSessionName! : accountName
    }
}
