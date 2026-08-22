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
private let changedFingerprint = Fingerprint.value(rawValue: "network en1 10.0.0.20 10.0.0.1")
private let thresholds = TunnelReducer.Thresholds(
    connectingDownGrace: 3,
    connectingTimeout: 30,
    connectedDownLimit: 2,
    networkTransitionLimit: 2
)

private func context(
    _ phase: TunnelState,
    downStreak: Int = 0,
    connectStart: Date? = nil,
    fingerprint: Fingerprint? = nil,
    networkTransitionStreak: Int = 0,
    reconnectAttempts: Int = 0,
    userInitiated: Bool = false,
    reconnectSession: Bool = false
) -> TunnelReducer.Context {
    .init(
        phase: phase,
        downStreak: downStreak,
        networkTransitionStreak: networkTransitionStreak,
        connectStart: connectStart,
        connectionNetworkFingerprint: fingerprint,
        reconnectAttempts: reconnectAttempts,
        userInitiated: userInitiated,
        reconnectSession: reconnectSession
    )
}

private func result(
    _ phase: TunnelState,
    downStreak: Int = 0,
    connectStart: Date? = nil,
    fingerprint: Fingerprint? = nil,
    networkTransitionStreak: Int = 0,
    reconnectAttempts: Int = 0,
    userInitiated: Bool = false,
    reconnectSession: Bool = false,
    effects: [TunnelReducer.Effect] = []
) -> TunnelReducer.Result {
    .init(
        state: context(
            phase,
            downStreak: downStreak,
            connectStart: connectStart,
            fingerprint: fingerprint,
            networkTransitionStreak: networkTransitionStreak,
            reconnectAttempts: reconnectAttempts,
            userInitiated: userInitiated,
            reconnectSession: reconnectSession
        ),
        effects: effects
    )
}

private func reduce(
    _ state: TunnelReducer.Context,
    _ event: TunnelReducer.Event
) -> TunnelReducer.Result {
    TunnelReducer.reduce(state: state, event: event, now: now, thresholds: thresholds)
}

// Literal expectations from the orchestration event table; the network-transition
// debounce expectations come from issue #23 (ADR-0003).
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
    "valid connect request marks the session user-initiated",
    result(.errTimeout, userInitiated: true, effects: [.readConnectionNetwork]),
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

let connected = context(.connected, connectStart: now, fingerprint: fingerprint)
check(
    "captured fingerprint updates reducer context",
    result(.connected, connectStart: now, fingerprint: fingerprint),
    reduce(connected, .fingerprintRead(.available(fingerprint)))
)
check(
    "captured fingerprint differing from the baseline begins network-change cleanup",
    result(.disconnecting, connectStart: now, fingerprint: fingerprint, effects: [.stopTunnel(after: .errNetworkChanged)]),
    reduce(connected, .fingerprintRead(.available(changedFingerprint)))
)
// 网络过渡防抖表 (issue #23 / ADR-0003): .unavailable/.failed 均视为指纹取不到。
check(
    "single unavailable capture is a tolerated transition",
    result(.connected, connectStart: now, fingerprint: fingerprint, networkTransitionStreak: 1),
    reduce(connected, .fingerprintRead(.unavailable))
)
check(
    "single failed capture is a tolerated transition",
    result(.connected, connectStart: now, fingerprint: fingerprint, networkTransitionStreak: 1),
    reduce(connected, .fingerprintRead(.failed))
)
check(
    "second consecutive unavailable capture begins network-change cleanup",
    result(.disconnecting, connectStart: now, fingerprint: fingerprint, effects: [.stopTunnel(after: .errNetworkChanged)]),
    reduce(context(.connected, connectStart: now, fingerprint: fingerprint, networkTransitionStreak: 1), .fingerprintRead(.unavailable))
)
check(
    "second consecutive failed capture begins network-change cleanup",
    result(.disconnecting, connectStart: now, fingerprint: fingerprint, effects: [.stopTunnel(after: .errNetworkChanged)]),
    reduce(context(.connected, connectStart: now, fingerprint: fingerprint, networkTransitionStreak: 1), .fingerprintRead(.failed))
)
check(
    "recovered capture read equal to the baseline clears the streak",
    result(.connected, connectStart: now, fingerprint: fingerprint),
    reduce(context(.connected, connectStart: now, fingerprint: fingerprint, networkTransitionStreak: 1), .fingerprintRead(.available(fingerprint)))
)
check(
    "capture read differing from the baseline after a transition still tears down immediately",
    result(.disconnecting, connectStart: now, fingerprint: fingerprint, effects: [.stopTunnel(after: .errNetworkChanged)]),
    reduce(context(.connected, connectStart: now, fingerprint: fingerprint, networkTransitionStreak: 1), .fingerprintRead(.available(changedFingerprint)))
)
let awaitingCapture = context(.connected, connectStart: now)
check(
    "capture without a baseline records the fingerprint without judging a change",
    result(.connected, connectStart: now, fingerprint: fingerprint),
    reduce(awaitingCapture, .fingerprintRead(.available(fingerprint)))
)
check(
    "capture without a baseline still treats unavailable as a network change",
    result(.disconnecting, connectStart: now, effects: [.stopTunnel(after: .errNetworkChanged)]),
    reduce(awaitingCapture, .fingerprintRead(.unavailable))
)
check(
    "capture config error is unconfigured",
    result(.disconnected, connectStart: now, effects: [.recordMissingConfigFields(["USER"])]),
    reduce(awaitingCapture, .fingerprintRead(.configError(missingFields: ["USER"])))
)

// 重连编排 (issue #24/#25 / ADR-0003): 防抖判变转 reconnecting——connecting 在飞尝试计入配额,
// 等待不计数,配额 3 次升红,auth 立停,取消走 disconnect。
let connectedSession = context(.connected, connectStart: now, fingerprint: fingerprint, userInitiated: true)
check(
    "debounced change in a user session tears down into reconnecting",
    result(.disconnecting, fingerprint: fingerprint, userInitiated: true, effects: [.stopTunnel(after: .reconnecting)]),
    reduce(connectedSession, .fingerprintRead(.available(changedFingerprint)))
)
check(
    "debounced change outside a user session keeps the red terminal state",
    result(.disconnecting, connectStart: now, fingerprint: fingerprint, effects: [.stopTunnel(after: .errNetworkChanged)]),
    reduce(context(.connected, connectStart: now, fingerprint: fingerprint), .fingerprintRead(.available(changedFingerprint)))
)
check(
    "debounced unavailability in a user session tears down into reconnecting",
    result(.disconnecting, fingerprint: fingerprint, userInitiated: true, effects: [.stopTunnel(after: .reconnecting)]),
    reduce(context(.connected, connectStart: now, fingerprint: fingerprint, networkTransitionStreak: 1, userInitiated: true), .fingerprintRead(.unavailable))
)
// connecting 途中判变 (issue #25): 与快照入口共用同一 teardown,在飞连接尝试计为第 1 次失败。
check(
    "change while connecting in a user session counts the abandoned attempt",
    result(
        .disconnecting, fingerprint: fingerprint, reconnectAttempts: 1, userInitiated: true,
        effects: [.stopTunnel(after: .reconnecting)]
    ),
    reduce(context(.connecting, connectStart: now, fingerprint: fingerprint, userInitiated: true), .fingerprintRead(.available(changedFingerprint)))
)

let reconnectingSession = context(.reconnecting, fingerprint: nil, userInitiated: true, reconnectSession: true)
check(
    "stopped teardown enters the reconnecting session and rereads the network",
    TunnelReducer.Result(
        state: context(.reconnecting, fingerprint: nil, userInitiated: true, reconnectSession: true),
        effects: [.clearMissingConfigFields, .readConnectionNetwork]
    ),
    reduce(context(.disconnecting, fingerprint: fingerprint, userInitiated: true), .stopCompleted(.stopped(wasRunning: true), after: .reconnecting))
)
check(
    "unavailable network while reconnecting keeps waiting without counting",
    TunnelReducer.Result(state: reconnectingSession, effects: []),
    reduce(reconnectingSession, .connectionNetworkRead(.unavailable))
)
check(
    "available network while reconnecting restarts connecting",
    result(.connecting, connectStart: now, fingerprint: fingerprint, userInitiated: true, reconnectSession: true, effects: [.startConnect]),
    reduce(reconnectingSession, .connectionNetworkRead(.available(fingerprint)))
)
check(
    "cancelling a reconnecting session runs the normal disconnect cleanup",
    result(.disconnecting, userInitiated: true, reconnectSession: true, effects: [.stopTunnel(after: .disconnected)]),
    reduce(reconnectingSession, .disconnectRequested(after: .disconnected))
)
check(
    "duplicate connect request while reconnecting is ignored",
    TunnelReducer.Result(state: reconnectingSession, effects: []),
    reduce(reconnectingSession, .connectRequested(profileConfigured: true, pinAvailable: true))
)

let reconnectingAttempt = context(.connecting, connectStart: now, fingerprint: fingerprint, userInitiated: true, reconnectSession: true)
check(
    "auth failure during reconnect stops immediately in red",
    result(.errAuth, connectStart: now, fingerprint: fingerprint, userInitiated: true),
    reduce(reconnectingAttempt, .startCompleted(.authenticationFailed))
)
check(
    "first failed attempt within the quota tears down and retries",
    TunnelReducer.Result(
        state: context(.disconnecting, connectStart: now, fingerprint: fingerprint, reconnectAttempts: 1, userInitiated: true, reconnectSession: true),
        effects: [.stopTunnel(after: .reconnecting)]
    ),
    reduce(reconnectingAttempt, .startFailed)
)
check(
    "third failed attempt exhausts the quota into terminal red",
    TunnelReducer.Result(
        state: context(.disconnecting, connectStart: now, fingerprint: fingerprint, reconnectAttempts: 3, userInitiated: true, reconnectSession: false),
        effects: [.stopTunnel(after: .errReconnectFailed)]
    ),
    reduce(context(.connecting, connectStart: now, fingerprint: fingerprint, reconnectAttempts: 2, userInitiated: true, reconnectSession: true), .startFailed)
)
check(
    "transport failure outside a reconnect session keeps timeout convergence",
    TunnelReducer.Result(
        state: context(.connecting, connectStart: now, fingerprint: fingerprint, userInitiated: true),
        effects: []
    ),
    reduce(context(.connecting, connectStart: now, fingerprint: fingerprint, userInitiated: true), .startFailed)
)

if assertions == 60 {
    print("  ok   all event assertions executed")
} else {
    failures += 1
    print("  FAIL all event assertions executed\n       expected: 60\n       actual:   \(assertions)")
}

if failures > 0 {
    print("\n\(failures) failed")
    exit(1)
}
print("\n\(assertions) event assertions passed")
