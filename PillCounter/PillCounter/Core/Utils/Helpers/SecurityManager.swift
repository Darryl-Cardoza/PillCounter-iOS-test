//
//  SecurityManager.swift
//  PillCounter
//
//  Created by HC on 29/12/25.
//

import Foundation
import UIKit

// MARK: - SECURITY MANAGER
/// Centralized utility responsible for detecting whether the device or app
/// environment is insecure or compromised.
struct SecurityManager {

    // MARK: - PUBLIC SECURITY CHECK
    /// Performs all security validations and returns `true`
    /// if the device or app environment is compromised.
    static func isDeviceCompromised() -> Bool {
        return isJailbroken()
            || isDebuggerAttached()
            || isRunningOnSimulator()
            || isTampered()
//        return false
    }

    // MARK: - JAILBREAK DETECTION
    /// Detects jailbreak indicators such as known system paths
    /// and attempts to write outside the app sandbox.
    private static func isJailbroken() -> Bool {

        #if targetEnvironment(simulator)
            // Simulator is treated as compromised for production builds
            return true
        #endif

        let jailbreakIndicators = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/",
        ]

        // Check for known jailbreak-related files
        for path in jailbreakIndicators {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }

        // Attempt to write outside the app sandbox (should fail on secure devices)
        let testPath = "/private/security_test.txt"
        do {
            try "test".write(
                toFile: testPath,
                atomically: true,
                encoding: .utf8
            )
            try FileManager.default.removeItem(atPath: testPath)
            return true
        } catch {
            return false
        }
    }

    // MARK: - DEBUGGER DETECTION
    /// Detects whether a debugger is attached to the running process.
    /// Commonly used to prevent runtime inspection and tampering.
    private static func isDebuggerAttached() -> Bool {

        #if DEBUG
            return false
        #endif

        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size

        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        sysctl(&mib, 4, &info, &size, nil, 0)

        return (info.kp_proc.p_flag & P_TRACED) != 0
    }

    // MARK: - SIMULATOR DETECTION
    /// Detects whether the app is running on a simulator.
    /// Typically blocked in production builds for security reasons.
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
    /// Detects whether the app bundle shows signs of re-signing
    /// or unauthorized modification.
    private static func isTampered() -> Bool {
        return Bundle.main.infoDictionary?["SignerIdentity"] != nil
    }
}

// MARK: - SECURITY MONITOR
/// Periodically monitors the security state at runtime
/// and triggers a callback if a violation is detected.
final class SecurityMonitor {

    static let shared = SecurityMonitor()
    private var timer: Timer?

    // MARK: - START MONITORING
    /// Starts periodic security checks and executes the
    /// provided closure upon detecting a violation.
    func startMonitoring(onViolation: @escaping () -> Void) {
        timer = Timer.scheduledTimer(
            withTimeInterval: 5,
            repeats: true
        ) { _ in
            if SecurityManager.isDeviceCompromised() {
                onViolation()
            }
        }
    }

    // MARK: - STOP MONITORING
    /// Stops active security monitoring and invalidates the timer.
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - SECURITY STATE
/// Observable security state used by SwiftUI
/// to block or allow app access.
final class AppSecurityState: ObservableObject {

    /// Indicates whether the device and app environment
    /// are considered secure.
    @Published var isSecure: Bool = true
}
