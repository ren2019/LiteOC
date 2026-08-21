import Darwin
import Foundation

enum VpnctlClientFailure: Error, Equatable {
    case configError(missingFields: [String])
    case unexpectedOutput(String)
    case spawnFailed
}

enum StatusSnapshot: Equatable {
    case down
    case routeStale
    case routeCheckFailed
    case connecting
    case connected(ip: String)
    case configError(missingFields: [String])
}

enum StartResult: Equatable {
    case started(discoveredCert: String?)
    case authenticationFailed
    case noPin
    case alreadyRunning
    case openconnectMissing
    case certificateDiscoveryFailed
    case routeFailure
    case stopTimeout
    case configError(missingFields: [String])
}

enum StopResult: Equatable {
    case stopped(wasRunning: Bool)
    case routeFailure
    case stopTimeout
    case configError(missingFields: [String])
}

enum RepairResult: Equatable {
    case alreadyRunning
    case repaired
    case clean
    case routeFailure
    case configError(missingFields: [String])
}

enum Fingerprint: Equatable {
    case value(rawValue: String)
}

struct VpnctlClient {
    let vpnctlPath: String
    let configPath: String
    let sudoPath: String

    init(vpnctlPath: String, configPath: String, sudoPath: String = "/usr/bin/sudo") {
        self.vpnctlPath = vpnctlPath
        self.configPath = configPath
        self.sudoPath = sudoPath
    }

    func status() throws -> StatusSnapshot {
        try Self.parseStatus(spawn(command: "status"))
    }

    func network() throws -> Fingerprint? {
        try Self.parseNetwork(spawn(command: "network"))
    }

    func start(pin: String) throws -> StartResult {
        try Self.parseStart(spawn(command: "start", stdin: pin))
    }

    func stop() throws -> StopResult {
        try Self.parseStop(spawn(command: "stop"))
    }

    func repair() throws -> RepairResult {
        try Self.parseRepair(spawn(command: "repair"))
    }

    static func parseStatus(_ output: String) throws -> StatusSnapshot {
        let lines = protocolLines(output)
        guard lines.count == 1 else { throw unexpected(output) }

        switch lines[0] {
        case "down": return .down
        case "route-stale": return .routeStale
        case "route-check-failed": return .routeCheckFailed
        case "connecting": return .connecting
        default:
            if let ip = payload(after: "connected ", in: lines[0]), isIPAddress(ip) {
                return .connected(ip: ip)
            }
            if let missingFields = missingFields(in: lines[0]) {
                return .configError(missingFields: missingFields)
            }
            throw unexpected(output)
        }
    }

    static func parseStart(_ output: String) throws -> StartResult {
        let lines = protocolLines(output)
        if lines.count == 2,
           let discoveredCert = payload(after: "discovered-cert:", in: lines[0]),
           isCertificatePin(discoveredCert),
           lines[1] == "started" {
            return .started(discoveredCert: discoveredCert)
        }
        guard lines.count == 1 else { throw unexpected(output) }

        switch lines[0] {
        case "started": return .started(discoveredCert: nil)
        case "auth-failed": return .authenticationFailed
        case "no-pin": return .noPin
        case "already-running": return .alreadyRunning
        case "cert-discover-failed": return .certificateDiscoveryFailed
        case "route-check-failed", "route-cleanup-failed": return .routeFailure
        case "stop-timeout": return .stopTimeout
        default:
            if lines[0] == "openconnect-not-found" || lines[0].hasPrefix("openconnect-not-found ") {
                return .openconnectMissing
            }
            if let missingFields = missingFields(in: lines[0]) {
                return .configError(missingFields: missingFields)
            }
            throw unexpected(output)
        }
    }

    static func parseStop(_ output: String) throws -> StopResult {
        let lines = protocolLines(output)
        guard lines.count == 1 else { throw unexpected(output) }

        switch lines[0] {
        case "stopped": return .stopped(wasRunning: true)
        case "not-running": return .stopped(wasRunning: false)
        case "route-check-failed", "route-cleanup-failed": return .routeFailure
        case "stop-timeout": return .stopTimeout
        default:
            if let missingFields = missingFields(in: lines[0]) {
                return .configError(missingFields: missingFields)
            }
            throw unexpected(output)
        }
    }

    static func parseRepair(_ output: String) throws -> RepairResult {
        let lines = protocolLines(output)
        guard lines.count == 1 else { throw unexpected(output) }

        switch lines[0] {
        case "already-running": return .alreadyRunning
        case "route-repaired": return .repaired
        case "route-clean": return .clean
        case "route-check-failed", "route-cleanup-failed": return .routeFailure
        default:
            if let missingFields = missingFields(in: lines[0]) {
                return .configError(missingFields: missingFields)
            }
            throw unexpected(output)
        }
    }

    static func parseNetwork(_ output: String) throws -> Fingerprint? {
        let lines = protocolLines(output)
        guard lines.count == 1 else { throw unexpected(output) }
        if lines[0] == "network-unavailable" { return nil }
        if let missingFields = missingFields(in: lines[0]) {
            throw VpnctlClientFailure.configError(missingFields: missingFields)
        }

        let parts = lines[0].split(whereSeparator: { $0.isWhitespace })
        guard parts.count == 4,
              parts[0] == "network",
              isIPAddress(String(parts[2])),
              isIPAddress(String(parts[3])) else {
            throw unexpected(output)
        }
        return .value(rawValue: lines[0])
    }

    private func spawn(command: String, stdin: String? = nil) throws -> String {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: vpnctlPath),
              fileManager.isExecutableFile(atPath: sudoPath) else {
            throw VpnctlClientFailure.spawnFailed
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: sudoPath)
        process.arguments = [vpnctlPath, command, configPath]
        let output = Pipe()
        let input = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = input

        do {
            try process.run()
        } catch {
            throw VpnctlClientFailure.spawnFailed
        }
        if let stdin, let data = stdin.data(using: .utf8) {
            input.fileHandleForWriting.write(data)
        }
        input.fileHandleForWriting.closeFile()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func protocolLines(_ output: String) -> [String] {
        output.split(separator: "\n").map {
            String($0).trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
    }

    private static func payload(after prefix: String, in line: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        let value = String(line.dropFirst(prefix.count))
        return value.isEmpty ? nil : value
    }

    private static func missingFields(in line: String) -> [String]? {
        guard let payload = payload(after: "config-error:缺 ", in: line) else { return nil }
        let fields = payload.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let allowedFields = Set(["HOST", "USER", "GROUP"])
        guard !fields.isEmpty,
              fields.allSatisfy(allowedFields.contains),
              Set(fields).count == fields.count else {
            return nil
        }
        return fields
    }

    private static func isIPAddress(_ value: String) -> Bool {
        var ipv4 = in_addr()
        if value.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 { return true }
        var ipv6 = in6_addr()
        return value.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1
    }

    private static func isCertificatePin(_ value: String) -> Bool {
        guard let digest = payload(after: "pin-sha256:", in: value) else { return false }
        return digest.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 65...90, 97...122, 43, 47, 61: return true
            default: return false
            }
        }
    }

    private static func unexpected(_ output: String) -> VpnctlClientFailure {
        .unexpectedOutput(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
