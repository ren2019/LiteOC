import Foundation

enum PinKeychainOperation: Equatable {
    case read
    case write
    case verify

    var label: String {
        switch self {
        case .read: return "读取"
        case .write: return "写入"
        case .verify: return "读回验证"
        }
    }
}

enum PinKeychainCategory: Equatable {
    case itemMissing
    case accessDenied
    case commandUnavailable
    case unknown
    case mismatch

    var label: String {
        switch self {
        case .itemMissing: return "条目不存在"
        case .accessDenied: return "钥匙串访问失败"
        case .commandUnavailable: return "系统命令无法启动"
        case .unknown: return "未知钥匙串错误"
        case .mismatch: return "读回值不一致"
        }
    }
}

struct PinKeychainFailure: Equatable, CustomStringConvertible {
    let operation: PinKeychainOperation
    let exitCode: Int?
    let category: PinKeychainCategory

    var description: String {
        let code = exitCode.map { "，退出码 \($0)" } ?? ""
        switch operation {
        case .read:
            return "钥匙串读取失败（\(category.label)\(code)）"
        case .write:
            return "钥匙串写入失败（\(category.label)\(code)）"
        case .verify:
            return "PIN 已写入，但无法验证（\(category.label)\(code)）"
        }
    }
}

enum PinKeychainCommandResult: Equatable {
    case exited(status: Int, output: String)
    case launchFailed
}

enum PinReadResult: Equatable {
    case value(String)
    case missing
    case failed(PinKeychainFailure)
}

enum PinSaveResult: Equatable {
    case verified
    case writeFailed(PinKeychainFailure)
    case verificationFailed(PinKeychainFailure)
}

struct PinKeychainStore {
    typealias Command = ([String]) -> PinKeychainCommandResult

    private static let commandQueue = DispatchQueue(label: "local.liteoc.keychain")
    private let account: String
    private let command: Command

    init(account: String = "pin", command: @escaping Command = Self.runSecurity) {
        self.account = account
        self.command = command
    }

    func read(service: String) -> PinReadResult {
        Self.commandQueue.sync { readWithoutQueue(service: service) }
    }

    func saveAndVerify(value: String, service: String) -> PinSaveResult {
        Self.commandQueue.sync {
            let write = command([
                "add-generic-password", "-s", service, "-a", account, "-w", value,
                "-T", "/usr/bin/security", "-U"
            ])
            guard case let .exited(status, _) = write else {
                return .writeFailed(failure(.write, category: .commandUnavailable))
            }
            guard status == 0 else {
                return .writeFailed(failure(.write, status: status))
            }

            switch readWithoutQueue(service: service, operation: .verify) {
            case let .value(readBack) where readBack == value:
                return .verified
            case .value:
                return .verificationFailed(failure(.verify, category: .mismatch))
            case .missing:
                return .verificationFailed(failure(.verify, status: 44))
            case let .failed(error):
                return .verificationFailed(error)
            }
        }
    }

    private func readWithoutQueue(
        service: String,
        operation: PinKeychainOperation = .read
    ) -> PinReadResult {
        let result = command([
            "find-generic-password", "-s", service, "-a", account, "-w"
        ])
        guard case let .exited(status, output) = result else {
            return .failed(failure(operation, category: .commandUnavailable))
        }
        guard status == 0 else {
            if status == 44 {
                return .missing
            }
            return .failed(failure(operation, status: status))
        }

        let value = output.removingOneTrailingLineBreak
        guard !value.isEmpty else {
            return .failed(failure(operation, category: .unknown))
        }
        return .value(value)
    }

    private func failure(
        _ operation: PinKeychainOperation,
        status: Int? = nil,
        category: PinKeychainCategory? = nil
    ) -> PinKeychainFailure {
        let safeCategory: PinKeychainCategory
        if let category {
            safeCategory = category
        } else if status == 44 && operation != .write {
            safeCategory = .itemMissing
        } else if status == 51 {
            // security returns errSecAuthFailed (-25293) as process status 51.
            // Keep this a Keychain access error; it is not a VPN PIN diagnosis.
            safeCategory = .accessDenied
        } else {
            safeCategory = .unknown
        }
        return PinKeychainFailure(operation: operation, exitCode: status, category: safeCategory)
    }

    private static func runSecurity(_ arguments: [String]) -> PinKeychainCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return .launchFailed
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return .exited(
            status: Int(process.terminationStatus),
            output: String(data: data, encoding: .utf8) ?? ""
        )
    }
}

private extension String {
    var removingOneTrailingLineBreak: String {
        if hasSuffix("\r\n") { return String(dropLast(2)) }
        if hasSuffix("\n") || hasSuffix("\r") { return String(dropLast()) }
        return self
    }
}

struct PinSaveGate {
    private(set) var generation = 0
    private var activeGeneration: Int?

    mutating func begin() -> Int? {
        guard activeGeneration == nil else { return nil }
        generation += 1
        activeGeneration = generation
        return generation
    }

    mutating func complete(_ request: Int) -> Bool {
        guard activeGeneration == request else { return false }
        activeGeneration = nil
        return true
    }

    mutating func invalidate() {
        generation += 1
        activeGeneration = nil
    }
}
