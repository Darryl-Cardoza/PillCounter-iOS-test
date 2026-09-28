import Foundation
import UIKit

/// Device/runtime metadata for the remote log payload. Several fields have no
/// existing source in this codebase and are documented stand-ins rather than a
/// silent guess — see the design spec §4 for the full rationale per field.
public enum DeviceInfoProvider {
    /// No real session concept exists in this app; a process-lifetime UUID is
    /// used as a stand-in so entries from the same launch can be grouped.
    public static let sessionId: String = UUID().uuidString

    public static var deviceKey: String {
        DeviceKeyProvider.shared.getDeviceKey()
    }

    public static var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "PillCounter"
    }

    public static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

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
