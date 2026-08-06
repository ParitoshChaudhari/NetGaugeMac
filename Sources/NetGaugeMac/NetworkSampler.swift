import Darwin
import Foundation

// MARK: - Data Structures

struct NetworkSnapshot: Equatable, Sendable {
    let bytesReceived: UInt64
    let bytesSent: UInt64
    let capturedAt: Date
    let interfaces: [InterfaceSnapshot]
}

struct InterfaceSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let displayName: String
    let bytesReceived: UInt64
    let bytesSent: UInt64
}

struct InterfaceRate: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let displayName: String
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double
}

enum NetworkSamplerError: Error {
    case interfaceReadFailed
    case interfaceDataMalformed
}

// MARK: - NetworkSampler

/// Reads kernel network interface counters using getifaddrs — the same source
/// as macOS Activity Monitor. Requires no special entitlements.
/// Marked Sendable: no mutable state; all methods are stateless reads.
final class NetworkSampler: Sendable {

    func snapshot() throws -> NetworkSnapshot {
        var ifList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifList) == 0, let head = ifList else {
            throw NetworkSamplerError.interfaceReadFailed
        }
        defer { freeifaddrs(ifList) }   // always freed even on early throw

        var totalReceived: UInt64 = 0
        var totalSent: UInt64 = 0
        var interfaceTotals: [String: InterfaceSnapshot] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = head

        while let current = cursor {
            let iface = current.pointee
            cursor = iface.ifa_next

            guard isUsable(iface), let rawData = iface.ifa_data else {
                continue
            }



            let data = rawData.assumingMemoryBound(to: if_data.self).pointee
            let ifReceived = UInt64(data.ifi_ibytes)
            let ifSent     = UInt64(data.ifi_obytes)

            // Interface name: getifaddrs guarantees null termination within IF_NAMESIZE bytes.
            guard let namePtr = iface.ifa_name else { continue }
            let name = String(cString: namePtr)

            // Use saturating addition to prevent silent overflow at ~18 EB totals.
            totalReceived = totalReceived.saturatingAdd(ifReceived)
            totalSent     = totalSent.saturatingAdd(ifSent)

            if let existing = interfaceTotals[name] {
                interfaceTotals[name] = InterfaceSnapshot(
                    id: name,
                    name: name,
                    displayName: existing.displayName,
                    bytesReceived: existing.bytesReceived.saturatingAdd(ifReceived),
                    bytesSent: existing.bytesSent.saturatingAdd(ifSent)
                )
            } else {
                interfaceTotals[name] = InterfaceSnapshot(
                    id: name,
                    name: name,
                    displayName: displayName(for: name),
                    bytesReceived: ifReceived,
                    bytesSent: ifSent
                )
            }
        }

        return NetworkSnapshot(
            bytesReceived: totalReceived,
            bytesSent: totalSent,
            capturedAt: Date(),
            interfaces: interfaceTotals.values.sorted { $0.name < $1.name }
        )
    }

    // MARK: – Helpers

    private func isUsable(_ iface: ifaddrs) -> Bool {
        let flags      = iface.ifa_flags
        let isUp       = (flags & UInt32(IFF_UP))       == UInt32(IFF_UP)
        let isLoopback = (flags & UInt32(IFF_LOOPBACK)) == UInt32(IFF_LOOPBACK)
        // AF_LINK sockets carry the if_data statistics we need.
        let hasLinkStats = iface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK)
        return isUp && !isLoopback && hasLinkStats
    }

    private func displayName(for name: String) -> String {
        // Prefix matching matches Apple's own interface naming convention.
        switch true {
        case name.hasPrefix("en"):     return "Wi-Fi / Ethernet (\(name))"
        case name.hasPrefix("utun"):   return "VPN Tunnel (\(name))"
        case name.hasPrefix("bridge"): return "Bridge (\(name))"
        case name.hasPrefix("awdl"):   return "Apple Wireless Direct Link (\(name))"
        case name.hasPrefix("llw"):    return "Low Latency Wi-Fi (\(name))"
        case name.hasPrefix("pdp"):    return "Cellular (\(name))"
        default:                       return name
        }
    }
}

// MARK: - UInt64 Saturating Add

private extension UInt64 {
    /// Adds `other` clamping at `UInt64.max` instead of wrapping or trapping.
    func saturatingAdd(_ other: UInt64) -> UInt64 {
        let (result, overflow) = self.addingReportingOverflow(other)
        return overflow ? .max : result
    }
}
