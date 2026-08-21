import Foundation

private var failures = 0
private var assertions = 0

private func check<T: Equatable>(_ description: String, _ expected: T, _ actual: T) {
    assertions += 1
    if expected == actual {
        print("  ok   \(description)")
    } else {
        failures += 1
        print("  FAIL \(description)\n       expected: \(expected)\n       actual:   \(actual)")
    }
}

private let now = Date(timeIntervalSince1970: 1_000)
private let fingerprint = Fingerprint.value(rawValue: "network en0 192.168.1.17 192.168.1.1")

private func context(
    _ phase: TunnelState,
    downStreak: Int = 0,
    connectStart: Date? = nil,
    fingerprint: Fingerprint? = nil
) -> TunnelReducer.Context {
    .init(
        phase: phase,
        downStreak: downStreak,
        connectStart: connectStart,
        connectionNetworkFingerprint: fingerprint
    )
}

private func result(
    _ phase: TunnelState,
    downStreak: Int = 0,
    connectStart: Date? = nil,
    fingerprint: Fingerprint? = nil,
    effects: [TunnelReducer.Effect] = []
) -> TunnelReducer.Result {
    .init(
        state: context(
            phase,
            downStreak: downStreak,
            connectStart: connectStart,
            fingerprint: fingerprint
        ),
        effects: effects
    )
}

private func reduce(
    _ state: TunnelReducer.Context,
    _ event: TunnelReducer.Event
) -> TunnelReducer.Result {
    TunnelReducer.reduce(state: state, event: event, now: now)
}

print("== TunnelReducer orchestration events ==")

check(
    "configured launch starts repair",
    result(.repairing, effects: [.repairTunnel]),
    reduce(context(.disconnected), .launch(profileConfigured: true))
)
check(
    "unconfigured launch remains disconnected",
    result(.disconnected),
    reduce(context(.disconnected), .launch(profileConfigured: false))
)

for repairResult in [RepairResult.alreadyRunning, .repaired, .clean] {
    check(
        "successful repair returns to disconnected and refreshes",
        result(.disconnected, effects: [.clearMissingConfigFields, .refreshStatus]),
        reduce(context(.repairing), .repairCompleted(repairResult))
    )
}
check(
    "repair route failure is visible",
    result(.errRoute),
    reduce(context(.repairing), .repairCompleted(.routeFailure))
)
check(
    "repair config error is unconfigured",
    result(.disconnected, effects: [.recordMissingConfigFields(["HOST"])]),
    reduce(context(.repairing), .repairCompleted(.configError(missingFields: ["HOST"])))
)
check(
    "repair transport failure is a route error",
    result(.errRoute),
    reduce(context(.repairing), .repairFailed)
)

check(
    "missing profile opens settings",
    result(.disconnected, effects: [.showSettings(focusPin: false)]),
    reduce(context(.errTimeout), .connectRequested(profileConfigured: false, pinAvailable: true))
)
check(
    "missing PIN opens focused settings",
    result(.disconnected, effects: [.showSettings(focusPin: true)]),
    reduce(context(.errTimeout), .connectRequested(profileConfigured: true, pinAvailable: false))
)
check(
    "valid connect request reads the network",
    result(.errTimeout, effects: [.readConnectionNetwork]),
    reduce(context(.errTimeout), .connectRequested(profileConfigured: true, pinAvailable: true))
)
let activeConnect = context(.connecting, connectStart: Date(timeIntervalSince1970: 990), fingerprint: fingerprint)
check(
    "duplicate connect request is ignored",
    TunnelReducer.Result(state: activeConnect, effects: []),
    reduce(activeConnect, .connectRequested(profileConfigured: true, pinAvailable: true))
)

check(
    "available network begins connecting",
    result(.connecting, connectStart: now, fingerprint: fingerprint, effects: [.startConnect]),
    reduce(context(.disconnected), .connectionNetworkRead(.available(fingerprint)))
)
check(
    "unavailable network is visible",
    result(.errNetworkChanged),
    reduce(context(.disconnected), .connectionNetworkRead(.unavailable))
)
check(
    "network config error is unconfigured",
    result(.disconnected, effects: [.recordMissingConfigFields(["GROUP"])]),
    reduce(context(.disconnected), .connectionNetworkRead(.configError(missingFields: ["GROUP"])))
)
check(
    "network read failure is a route error",
    result(.errRoute),
    reduce(context(.disconnected), .connectionNetworkRead(.failed))
)

let connecting = context(.connecting, connectStart: now, fingerprint: fingerprint)
let connectingResult = TunnelReducer.Result(state: connecting, effects: [.clearMissingConfigFields])
check("started waits for status", connectingResult, reduce(connecting, .startCompleted(.started(discoveredCert: nil))))
check("already running waits for status", connectingResult, reduce(connecting, .startCompleted(.alreadyRunning)))
check("legacy stop-timeout result still waits", connectingResult, reduce(connecting, .startCompleted(.stopTimeout)))
check(
    "discovered certificate is persisted",
    TunnelReducer.Result(
        state: connecting,
        effects: [.persistCertificate("pin-sha256:abc="), .clearMissingConfigFields]
    ),
    reduce(connecting, .startCompleted(.started(discoveredCert: "pin-sha256:abc=")))
)
check("authentication failure is visible", result(.errAuth, connectStart: now, fingerprint: fingerprint), reduce(connecting, .startCompleted(.authenticationFailed)))
check("certificate failure is visible", result(.errCert, connectStart: now, fingerprint: fingerprint), reduce(connecting, .startCompleted(.certificateDiscoveryFailed)))
check(
    "missing openconnect returns disconnected and alerts",
    result(.disconnected, connectStart: now, fingerprint: fingerprint, effects: [.alert(.openconnectMissing)]),
    reduce(connecting, .startCompleted(.openconnectMissing))
)
check("helper no-pin returns disconnected", result(.disconnected, connectStart: now, fingerprint: fingerprint), reduce(connecting, .startCompleted(.noPin)))
check("start route failure is visible", result(.errRoute, connectStart: now, fingerprint: fingerprint), reduce(connecting, .startCompleted(.routeFailure)))
check(
    "start config error is unconfigured",
    result(.disconnected, connectStart: now, fingerprint: fingerprint, effects: [.recordMissingConfigFields(["USER"])]),
    reduce(connecting, .startCompleted(.configError(missingFields: ["USER"])))
)
check("start transport failure keeps timeout convergence", TunnelReducer.Result(state: connecting, effects: []), reduce(connecting, .startFailed))

let cancelledConnect = context(.disconnecting, connectStart: now, fingerprint: fingerprint)
check(
    "late discovered certificate is persisted after cancellation",
    TunnelReducer.Result(
        state: cancelledConnect,
        effects: [.persistCertificate("pin-sha256:late=")]
    ),
    reduce(cancelledConnect, .startCompleted(.started(discoveredCert: "pin-sha256:late=")))
)
check(
    "late non-certificate start result does not change cancelled state",
    TunnelReducer.Result(state: cancelledConnect, effects: []),
    reduce(cancelledConnect, .startCompleted(.authenticationFailed))
)

check(
    "disconnect request starts stop effect",
    result(.disconnecting, connectStart: now, fingerprint: fingerprint, effects: [.stopTunnel(after: .disconnected)]),
    reduce(connecting, .disconnectRequested(after: .disconnected))
)
let disconnecting = context(.disconnecting, connectStart: now, fingerprint: fingerprint)
check(
    "duplicate disconnect request is ignored",
    TunnelReducer.Result(state: disconnecting, effects: []),
    reduce(disconnecting, .disconnectRequested(after: .disconnected))
)
check(
    "successful stop enters requested state and clears fingerprint",
    result(.errNetworkChanged, connectStart: now, effects: [.clearMissingConfigFields]),
    reduce(disconnecting, .stopCompleted(.stopped(wasRunning: true), after: .errNetworkChanged))
)
check("stop timeout is visible", result(.errStop, connectStart: now), reduce(disconnecting, .stopCompleted(.stopTimeout, after: .disconnected)))
check("stop route failure is visible", result(.errRoute, connectStart: now), reduce(disconnecting, .stopCompleted(.routeFailure, after: .disconnected)))
check(
    "stop config error is unconfigured",
    result(.disconnected, connectStart: now, effects: [.recordMissingConfigFields(["HOST", "GROUP"])]),
    reduce(disconnecting, .stopCompleted(.configError(missingFields: ["HOST", "GROUP"]), after: .disconnected))
)
check("stop transport failure is a route error", result(.errRoute, connectStart: now), reduce(disconnecting, .stopFailed))

let connected = context(.connected, connectStart: now)
check(
    "captured fingerprint updates reducer context",
    result(.connected, connectStart: now, fingerprint: fingerprint),
    reduce(connected, .fingerprintRead(.available(fingerprint)))
)
check(
    "unavailable capture begins network-change cleanup",
    result(.disconnecting, connectStart: now, effects: [.stopTunnel(after: .errNetworkChanged)]),
    reduce(connected, .fingerprintRead(.unavailable))
)
check(
    "failed capture begins network-change cleanup",
    result(.disconnecting, connectStart: now, effects: [.stopTunnel(after: .errNetworkChanged)]),
    reduce(connected, .fingerprintRead(.failed))
)
check(
    "capture config error is unconfigured",
    result(.disconnected, connectStart: now, effects: [.recordMissingConfigFields(["USER"])]),
    reduce(connected, .fingerprintRead(.configError(missingFields: ["USER"])))
)

if assertions == 40 {
    print("  ok   all event assertions executed")
} else {
    failures += 1
    print("  FAIL all event assertions executed\n       expected: 40\n       actual:   \(assertions)")
}

if failures > 0 {
    print("\n\(failures) failed")
    exit(1)
}
print("\n\(assertions) event assertions passed")
