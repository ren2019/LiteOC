import Foundation

private var failures = 0
private var assertions = 0

private func check(_ description: String, _ condition: Bool) {
    assertions += 1
    if condition {
        print("  ok   \(description)")
    } else {
        failures += 1
        print("  FAIL \(description)")
    }
}

final class FakeSecurity {
    var item: String?
    var writeResult: PinKeychainCommandResult = .exited(status: 0, output: "")
    var readResults: [PinKeychainCommandResult] = []
    private(set) var calls: [[String]] = []

    func run(_ arguments: [String]) -> PinKeychainCommandResult {
        calls.append(arguments)
        if arguments.first == "add-generic-password" {
            guard case .exited(status: 0, _) = writeResult else { return writeResult }
            guard let passwordFlag = arguments.firstIndex(of: "-w"), arguments.indices.contains(passwordFlag + 1) else {
                return .exited(status: 99, output: "")
            }
            item = arguments[passwordFlag + 1]
            return writeResult
        }
        if !readResults.isEmpty { return readResults.removeFirst() }
        guard let item else { return .exited(status: 44, output: "") }
        return .exited(status: 0, output: item + "\n")
    }
}

func store(_ fake: FakeSecurity) -> PinKeychainStore {
    PinKeychainStore(command: fake.run)
}

print("== PIN Keychain read/write contract ==")

let readFake = FakeSecurity()
readFake.item = "  existing-pin  "
check("read preserves the stored value except the command line ending", store(readFake).read(service: "test") == .value("  existing-pin  "))

let missingFake = FakeSecurity()
check("only the item-not-found status is treated as missing", store(missingFake).read(service: "test") == .missing)

let deniedFake = FakeSecurity()
deniedFake.readResults = [.exited(status: 51, output: "secret-bearing failure output")]
if case let .failed(error) = store(deniedFake).read(service: "test") {
    check("access failure retains read stage, status, and safe category", error.operation == .read && error.exitCode == 51 && error.category == .accessDenied)
    check("access failure does not expose command output", !error.description.contains("secret-bearing failure output"))
} else {
    check("access failure retains read stage, status, and safe category", false)
    check("access failure does not expose command output", false)
}

let unknownFake = FakeSecurity()
unknownFake.readResults = [.exited(status: 77, output: "secret-bearing failure output")]
if case let .failed(error) = store(unknownFake).read(service: "test") {
    check("unknown status remains an unknown Keychain error", error.exitCode == 77 && error.category == .unknown)
} else {
    check("unknown status remains an unknown Keychain error", false)
}

let unavailableFake = FakeSecurity()
unavailableFake.readResults = [.launchFailed]
if case let .failed(error) = store(unavailableFake).read(service: "test") {
    check("process launch failure is distinct from a missing item", error.exitCode == nil && error.category == .commandUnavailable)
} else {
    check("process launch failure is distinct from a missing item", false)
}

let createFake = FakeSecurity()
let candidatePin = "created-test-pin"
var createSession = PinSaveSession()
let createRequest = createSession.begin()
let createResult = store(createFake).saveAndVerify(value: candidatePin, service: "test")
let createOutcome = createRequest.flatMap { createSession.complete($0, result: createResult) }
check("new PIN succeeds only after write and matching read-back", createOutcome == .saved)
check("verified settings save clears input and calls the success callback", createOutcome?.clearsInput == true && createOutcome?.callsSuccessCallback == true)
check("successful create performs exactly one write and one read", createFake.calls.count == 2)
check("successful create stores the requested value", createFake.item == candidatePin)

let updateFake = FakeSecurity()
updateFake.item = "old-test-pin"
check("PIN update succeeds after the new value reads back", store(updateFake).saveAndVerify(value: candidatePin, service: "test") == .verified)

let failedWriteFake = FakeSecurity()
failedWriteFake.item = "old-test-pin"
failedWriteFake.writeResult = .exited(status: 51, output: "created-test-pin in private error output")
var failedWriteSession = PinSaveSession()
let failedWriteRequest = failedWriteSession.begin()
let failedWriteResult = store(failedWriteFake).saveAndVerify(value: candidatePin, service: "test")
let failedWriteOutcome = failedWriteRequest.flatMap { failedWriteSession.complete($0, result: failedWriteResult) }
if case let .failed(message) = failedWriteOutcome {
    if case let .writeFailed(error) = failedWriteResult {
        check("old readable item cannot hide a failed write", error.operation == .write && error.exitCode == 51 && failedWriteFake.calls.count == 1)
    } else {
        check("old readable item cannot hide a failed write", false)
    }
    check("write failure retains input and does not call success callback", failedWriteOutcome?.clearsInput == false && failedWriteOutcome?.callsSuccessCallback == false)
    check("write failure summary contains no PIN or raw output", !message.contains(candidatePin) && !message.contains("private error output"))
} else {
    check("old readable item cannot hide a failed write", false)
    check("write failure retains input and does not call success callback", false)
    check("write failure summary contains no PIN or raw output", false)
}

let launchFailureWriteFake = FakeSecurity()
launchFailureWriteFake.item = "old-test-pin"
launchFailureWriteFake.writeResult = .launchFailed
if case let .writeFailed(error) = store(launchFailureWriteFake).saveAndVerify(value: candidatePin, service: "test") {
    check("write process launch failure is distinct from an unsuccessful write status", error.operation == .write && error.exitCode == nil && error.category == .commandUnavailable)
} else {
    check("write process launch failure is distinct from an unsuccessful write status", false)
}

let verifyReadFailureFake = FakeSecurity()
verifyReadFailureFake.readResults = [.exited(status: 51, output: "created-test-pin in private error output")]
if case let .verificationFailed(error) = store(verifyReadFailureFake).saveAndVerify(value: candidatePin, service: "test") {
    check("write success followed by read failure is reported as unverified", error.operation == .verify && error.exitCode == 51)
    check("verification failure summary contains no PIN or raw output", !error.description.contains(candidatePin) && !error.description.contains("private error output"))
} else {
    check("write success followed by read failure is reported as unverified", false)
    check("verification failure summary contains no PIN or raw output", false)
}

let mismatchFake = FakeSecurity()
mismatchFake.readResults = [.exited(status: 0, output: "different-test-pin\n")]
if case let .verificationFailed(error) = store(mismatchFake).saveAndVerify(value: candidatePin, service: "test") {
    check("mismatched read-back is not reported as saved", error.operation == .verify && error.category == .mismatch)
} else {
    check("mismatched read-back is not reported as saved", false)
}

var gate = PinSaveSession()
let firstSave = gate.begin()
check("save gate accepts the first submission", firstSave != nil)
check("save gate blocks a duplicate submission", gate.begin() == nil)
if let firstSave {
    check("save completion releases the gate", gate.complete(firstSave, result: .verified) == .saved)
}
let staleSave = gate.begin()
gate.invalidate()
let nextSave = gate.begin()
check("closing invalidates the active save result", staleSave.map { gate.complete($0, result: .verified) == nil } == true)
check("a stale completion cannot release a newer save", nextSave.map { gate.complete($0, result: .verified) == .saved } == true)

print("\n\(assertions - failures) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
