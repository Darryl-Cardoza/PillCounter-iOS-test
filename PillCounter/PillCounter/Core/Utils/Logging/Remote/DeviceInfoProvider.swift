import Foundation
import MachO
import UIKit

/// Device/runtime metadata for the remote log payload. Several fields have no
/// existing source in this codebase and are documented stand-ins rather than a
/// silent guess — see the design spec §4 for the full rationale per field.
public enum DeviceInfoProvider {
    /// Log-grouping id, not an auth session: new on every launch, and rotated
    /// on login and logout so each user session's entries group separately.
    public static var sessionId: String {
        sessionLock.lock(); defer { sessionLock.unlock() }
        return currentSessionId
    }

    @discardableResult
    private static func rotateSession() -> String {
        sessionLock.lock(); defer { sessionLock.unlock() }
        currentSessionId = UUID().uuidString
        return currentSessionId
    }

    /// Rotates the id and writes a SESSION_STARTED marker (new id in `session_id`,
    /// old one in context) so sessions can be linked even when no errors occur.
    public static func startNewSession(reason: String) {
        let previous = sessionId
        rotateSession()
        logSessionStart(reason: reason, previous: previous)
    }

    public static func logLaunchSession() {
        logSessionStart(reason: "launch", previous: nil)
    }

    private static func logSessionStart(reason: String, previous: String?) {
        var context: [String: Any] = ["reason": reason]
        if let previous { context["previous_session_id"] = previous }
        AppLogger.shared.info("Session started", event: .sessionStarted, context: context)
    }

    private static let sessionLock = NSLock()
    private static var currentSessionId = UUID().uuidString

    public static var deviceKey: String {
        DeviceKeyProvider.shared.getDeviceKey()
    }

    // /mobile/logs only accepts "dispensesure" or "dispensesure_companion" (422 otherwise);
    // this target is the retail DispenseSure app, so a bundle-derived name won't validate.
    public static let appName = "dispensesure"

    public static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    /// Main executable's LC_UUID: unique per build and equal to its dSYM's UUID,
    /// which version/build numbers are not.
    public static var buildNumber: String? { mainExecutableUUID }

    private static let mainExecutableUUID: String? = {
        guard let header = _dyld_get_image_header(0) else { return nil } // image 0 is the main executable
        let header64 = UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self)
        var cursor = UnsafeRawPointer(header) + MemoryLayout<mach_header_64>.size
        for _ in 0..<header64.pointee.ncmds {
            let command = cursor.assumingMemoryBound(to: load_command.self).pointee
            if command.cmd == UInt32(LC_UUID) {
                return UUID(uuid: cursor.assumingMemoryBound(to: uuid_command.self).pointee.uuid).uuidString
            }
            cursor += Int(command.cmdsize)
        }
        return nil
    }()

    public static var platform: String { "iOS" }

    public static var osVersion: String {
        UIDevice.current.systemVersion
    }

    /// `UIDevice.current.model` only returns the generic "iPhone"; sysctl gives
    /// the specific hardware identifier (e.g. "iPhone15,3").
    public static var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        return machineMirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
    }
}
