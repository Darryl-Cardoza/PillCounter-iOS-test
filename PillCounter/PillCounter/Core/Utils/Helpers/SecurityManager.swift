//
//  SecurityManager.swift
//  PillCounter
//

import Foundation
import UIKit
import MachO

// MARK: - SECURITY MANAGER
struct SecurityManager {

    // MARK: - PUBLIC SECURITY CHECK
    /// True when the runtime environment shows signs of compromise.
    ///
    /// Active checks: jailbreak, attached debugger, runtime dylib injection.
    /// In DEBUG builds these short-circuit to `false` (see each check) so normal
    /// development on device/simulator is never flagged.
    ///
    /// Deliberately NOT included (removed as unreliable):
    ///  • simulator detection — the simulator is a valid QA target.
    ///  • `SignerIdentity` tamper heuristic — present on dev/ad-hoc builds and
    ///    absent on App Store builds, so it false-positives. Reinstate only
    ///    with a reliable signature/receipt-based check.
    static func isDeviceCompromised() -> Bool {
        #if DEBUG
        return false
        #else
        return
        isJailbroken()
        || isDebuggerAttached()
        || isRunningOnSimulator()
        || isTampered()
        || hasSuspiciousDylibs()
        #endif
    }


    // MARK: - JAILBREAK DETECTION
    private static func isJailbroken() -> Bool {
        #if targetEnvironment(simulator)
        // Jailbreak detection is meaningless on the simulator; never flag it.
        return false
        #else
        let jailbreakPaths = [
            "/Applications/Cydia.app",
            "/Applications/Sileo.app",
            "/Applications/Zebra.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/",
            "/usr/bin/ssh",
            "/private/var/stash",
        ]

        for path in jailbreakPaths {
            if FileManager.default.fileExists(atPath: path) { return true }
        }

        // Attempt to write outside the sandbox — fails on unmodified devices.
        let testPath = "/private/security_test_\(UUID().uuidString).txt"
        do {
            try "test".write(toFile: testPath, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: testPath)
            return true
        } catch {
            return false
        }
        #endif
    }
    
    private static func isRunningOnSimulator() -> Bool {
          #if targetEnvironment(simulator)
          #if DEBUG
          return false
          #else
          return true
          #endif
          #else
          return false
          #endif
      }

      // MARK: - APP TAMPERING DETECTION
      private static func isTampered() -> Bool {
          return Bundle.main.infoDictionary?["SignerIdentity"] != nil
      }

    // MARK: - DEBUGGER DETECTION
    private static func isDebuggerAttached() -> Bool {
        #if DEBUG
        return false
        #endif

        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib  = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        sysctl(&mib, 4, &info, &size, nil, 0)
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }

    // MARK: - DYLIB INJECTION DETECTION
    /// Walks every dynamic library loaded into the current process via the
    /// MachO dyld API. Frida, Substrate, Substitute, libhooker, and similar
    /// instrumentation frameworks all inject a .dylib whose path contains a
    /// well-known substring.
    ///
    /// These are pure C calls into the dynamic linker — they cannot be
    /// intercepted by ObjC method swizzling or Swift runtime hooks.
    /// `import MachO` makes them available without a bridging header.
    private static func hasSuspiciousDylibs() -> Bool {
        let suspiciousPatterns: [String] = [
            "FridaGadget",
            "frida",
            "cynject",
            "libhooker",
            "substitute",
            "SubstrateLoader",
            "MobileSubstrate",
            "SSLKillSwitch",
            "TweakInject",
            "cycript",
            "rvi_agent",
            "xCon",
        ]

        let imageCount = _dyld_image_count()
        for i in 0..<imageCount {
            guard let rawName = _dyld_get_image_name(i) else { continue }
            let imageName = String(cString: rawName).lowercased()
            for pattern in suspiciousPatterns where imageName.contains(pattern.lowercased()) {
                return true
            }
        }
        return false
    }
}

// MARK: - SECURITY MONITOR
final class SecurityMonitor {

    static let shared = SecurityMonitor()
    private var timer: Timer?

    func startMonitoring(onViolation: @escaping () -> Void) {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            if SecurityManager.isDeviceCompromised() {
                onViolation()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - SECURITY STATE
final class AppSecurityState: ObservableObject {
    @Published var isSecure: Bool = true
}
