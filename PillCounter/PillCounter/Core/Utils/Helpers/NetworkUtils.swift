//
//  NetworksUtils.swift
//  PillCounter
//
//  Created by Bhushan Patil on 16/04/26.
//
import Network

// MARK: - Native Network Utils
// iOS equivalent of Android's NetworkUtils.getLocalIpAddress()

enum NetworkUtils {
    /// Returns the device's current Wi-Fi / LAN IPv4 address, or nil if unavailable.
    /// Prefers en0 (Wi-Fi), falls back to en1. Skips loopback (127.x.x.x).
    static func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = firstAddr
        while true {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                // en0 = Wi-Fi, en1 = Ethernet adapter (iPad etc.)
                if name == "en0" || (address == nil && name == "en1") {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    ) == 0 {
                        address = String(cString: hostname)
                    }
                    // Stop as soon as we find en0
                    if name == "en0" { break }
                }
            }

            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }

        return address
    }
}
