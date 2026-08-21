import Foundation

var failures = 0

func check<T: Equatable>(_ description: String, _ expected: T, _ actual: T) {
    if expected == actual {
        print("  ok   \(description)")
    } else {
        failures += 1
        print("  FAIL \(description)\n       expected: \(expected)\n       actual:   \(actual)")
    }
}

func capture<T>(_ body: () throws -> T) -> Result<T, VpnctlClientFailure> {
    do {
        return .success(try body())
    } catch let failure as VpnctlClientFailure {
        return .failure(failure)
    } catch {
        fatalError("unexpected error type: \(error)")
    }
}

func parseStatus(_ output: String) -> Result<StatusSnapshot, VpnctlClientFailure> {
    capture { try VpnctlClient.parseStatus(output) }
}

func parseStart(_ output: String) -> Result<StartResult, VpnctlClientFailure> {
    capture { try VpnctlClient.parseStart(output) }
}

func parseStop(_ output: String) -> Result<StopResult, VpnctlClientFailure> {
    capture { try VpnctlClient.parseStop(output) }
}

func parseRepair(_ output: String) -> Result<RepairResult, VpnctlClientFailure> {
    capture { try VpnctlClient.parseRepair(output) }
}

func parseNetwork(_ output: String) -> Result<Fingerprint?, VpnctlClientFailure> {
    capture { try VpnctlClient.parseNetwork(output) }
}

print("== VpnctlClient protocol contract ==")

check("status down", .success(.down), parseStatus("down\n"))
check("status route-stale", .success(.routeStale), parseStatus("route-stale\n"))
check("status route-check-failed", .success(.routeCheckFailed), parseStatus("route-check-failed\n"))
check("status connecting", .success(.connecting), parseStatus("connecting\n"))
check("status connected carries IP", .success(.connected(ip: "192.0.2.42")), parseStatus("connected 192.0.2.42\n"))
check("status connected accepts IPv6", .success(.connected(ip: "2001:db8::42")), parseStatus("connected 2001:db8::42\n"))
check(
    "status config-error carries missing fields",
    .success(.configError(missingFields: ["HOST", "GROUP"])),
    parseStatus("config-error:缺 HOST GROUP\n")
)

check("start started", .success(.started(discoveredCert: nil)), parseStart("started\n"))
check(
    "start carries discovered cert",
    .success(.started(discoveredCert: "pin-sha256:abcDEF+/==")),
    parseStart("discovered-cert:pin-sha256:abcDEF+/==\nstarted\n")
)
check("start auth-failed", .success(.authenticationFailed), parseStart("auth-failed\n"))
check("start no-pin", .success(.noPin), parseStart("no-pin\n"))
check("start already-running", .success(.alreadyRunning), parseStart("already-running\n"))
check(
    "start openconnect-not-found",
    .success(.openconnectMissing),
    parseStart("openconnect-not-found (重新运行 LiteOC 安装器)\n")
)
check(
    "start cert-discover-failed",
    .success(.certificateDiscoveryFailed),
    parseStart("cert-discover-failed\n")
)
check("start route-check-failed", .success(.routeFailure), parseStart("route-check-failed\n"))
check("start route-cleanup-failed", .success(.routeFailure), parseStart("route-cleanup-failed\n"))
check("start stop-timeout", .success(.stopTimeout), parseStart("stop-timeout\n"))
check(
    "start config-error",
    .success(.configError(missingFields: ["USER"])),
    parseStart("config-error:缺 USER\n")
)

check("stop stopped", .success(.stopped(wasRunning: true)), parseStop("stopped\n"))
check("stop not-running", .success(.stopped(wasRunning: false)), parseStop("not-running\n"))
check("stop stop-timeout", .success(.stopTimeout), parseStop("stop-timeout\n"))
check("stop route-check-failed", .success(.routeFailure), parseStop("route-check-failed\n"))
check("stop route-cleanup-failed", .success(.routeFailure), parseStop("route-cleanup-failed\n"))
check(
    "stop config-error",
    .success(.configError(missingFields: ["HOST", "USER"])),
    parseStop("config-error:缺 HOST USER\n")
)

check("repair already-running", .success(.alreadyRunning), parseRepair("already-running\n"))
check("repair route-repaired", .success(.repaired), parseRepair("route-repaired\n"))
check("repair route-clean", .success(.clean), parseRepair("route-clean\n"))
check("repair route-check-failed", .success(.routeFailure), parseRepair("route-check-failed\n"))
check("repair route-cleanup-failed", .success(.routeFailure), parseRepair("route-cleanup-failed\n"))
check(
    "repair config-error",
    .success(.configError(missingFields: ["GROUP"])),
    parseRepair("config-error:缺 GROUP\n")
)

check(
    "network fingerprint",
    .success(.value(rawValue: "network en0 192.168.1.17 192.168.1.1")),
    parseNetwork("network en0 192.168.1.17 192.168.1.1\n")
)
check("network unavailable", .success(nil), parseNetwork("network-unavailable\n"))
check(
    "network config-error is explicit failure",
    .failure(.configError(missingFields: ["HOST"])),
    parseNetwork("config-error:缺 HOST\n")
)

check("status unknown output", .failure(.unexpectedOutput("mystery")), parseStatus("mystery\n"))
check("start unknown output", .failure(.unexpectedOutput("mystery")), parseStart("mystery\n"))
check("stop unknown output", .failure(.unexpectedOutput("mystery")), parseStop("mystery\n"))
check("repair unknown output", .failure(.unexpectedOutput("mystery")), parseRepair("mystery\n"))
check("network unknown output", .failure(.unexpectedOutput("mystery")), parseNetwork("mystery\n"))
check(
    "status rejects malformed IP payload",
    .failure(.unexpectedOutput("connected garbage")),
    parseStatus("connected garbage\n")
)
check(
    "start rejects malformed cert payload",
    .failure(.unexpectedOutput("discovered-cert:garbage\nstarted")),
    parseStart("discovered-cert:garbage\nstarted\n")
)
check(
    "start rejects characters outside the cert contract",
    .failure(.unexpectedOutput("discovered-cert:pin-sha256:abc-\nstarted")),
    parseStart("discovered-cert:pin-sha256:abc-\nstarted\n")
)
check(
    "network rejects malformed fingerprint payload",
    .failure(.unexpectedOutput("network a b c")),
    parseNetwork("network a b c\n")
)
check(
    "config-error rejects fields outside the Profile contract",
    .failure(.unexpectedOutput("config-error:缺 SERVERCERT")),
    parseStatus("config-error:缺 SERVERCERT\n")
)

let fixtureDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("liteoc-vpnctl-client-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: fixtureDirectory) }

let helperURL = fixtureDirectory.appendingPathComponent("vpnctl")
let runnerURL = fixtureDirectory.appendingPathComponent("sudo")
let largeRunnerURL = fixtureDirectory.appendingPathComponent("large-stdout-sudo")
let nonExecutableURL = fixtureDirectory.appendingPathComponent("not-executable")
try! "#!/bin/sh\nexit 0\n".write(to: helperURL, atomically: true, encoding: .utf8)
try! "not executable\n".write(to: nonExecutableURL, atomically: true, encoding: .utf8)
let runner = #"""
#!/bin/sh
printf 'ignored stderr\n' >&2
case "$2" in
  status) printf 'down\n'; exit 23 ;;
  network) printf 'network en0 192.168.1.17 192.168.1.1\n' ;;
  start) [ "$(cat)" = "test-pin" ] && printf 'started\n' || printf 'wrong-pin\n' ;;
  stop) printf 'stopped\n' ;;
  repair) printf 'route-clean\n' ;;
esac
"""#
try! runner.write(to: runnerURL, atomically: true, encoding: .utf8)
let largeRunner = #"""
#!/bin/sh
/usr/bin/awk 'BEGIN { for (i = 0; i < 131072; i++) printf "x"; printf "\n" }'
"""#
try! largeRunner.write(to: largeRunnerURL, atomically: true, encoding: .utf8)
try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)
try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runnerURL.path)
try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: largeRunnerURL.path)

let client = VpnctlClient(
    vpnctlPath: helperURL.path,
    configPath: fixtureDirectory.appendingPathComponent("config").path,
    sudoPath: runnerURL.path
)
check("adapter parses stdout despite nonzero exit and stderr", .success(.down), capture { try client.status() })
check(
    "adapter network",
    .success(.value(rawValue: "network en0 192.168.1.17 192.168.1.1")),
    capture { try client.network() }
)
check("adapter start sends PIN on stdin", .success(.started(discoveredCert: nil)), capture { try client.start(pin: "test-pin") })
check("adapter stop", .success(.stopped(wasRunning: true)), capture { try client.stop() })
check("adapter repair", .success(.clean), capture { try client.repair() })

let missingClient = VpnctlClient(
    vpnctlPath: fixtureDirectory.appendingPathComponent("missing").path,
    configPath: "unused",
    sudoPath: runnerURL.path
)
check("missing executable is spawn failure", .failure(.spawnFailed), capture { try missingClient.status() })

let nonExecutableClient = VpnctlClient(
    vpnctlPath: nonExecutableURL.path,
    configPath: "unused",
    sudoPath: runnerURL.path
)
check("non-executable is same spawn failure", .failure(.spawnFailed), capture { try nonExecutableClient.network() })

let largeOutputClient = VpnctlClient(
    vpnctlPath: helperURL.path,
    configPath: "unused",
    sudoPath: largeRunnerURL.path
)
let largeOutputStartedAt = Date()
let largeOutputResult = capture { try largeOutputClient.status() }
check("large stdout is drained promptly", true, Date().timeIntervalSince(largeOutputStartedAt) < 5)
switch largeOutputResult {
case let .failure(.unexpectedOutput(payload)):
    check("large stdout remains an explicit failure", 131072, payload.count)
default:
    failures += 1
    print("  FAIL large stdout remains an explicit failure\n       actual: \(largeOutputResult)")
}

if failures > 0 {
    print("\n\(failures) failed")
    exit(1)
}
print("\nall passed")
