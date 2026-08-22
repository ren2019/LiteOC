import Foundation

private var failures = 0
private var matrixAssertions = 0
private var boundaryAssertions = 0

private func check<T: Equatable>(_ description: String, _ expected: T, _ actual: T, boundary: Bool = false) {
    if expected == actual {
        print("  ok   \(description)")
    } else {
        failures += 1
        print("  FAIL \(description)\n       expected: \(expected)\n       actual:   \(actual)")
    }
    if boundary { boundaryAssertions += 1 }
}

private let now = Date(timeIntervalSince1970: 1_000)
private let connectStart = Date(timeIntervalSince1970: 999)
private let baseline = Fingerprint.value(rawValue: "network en0 192.168.1.17 192.168.1.1")
private let changedNetwork = Fingerprint.value(rawValue: "network en1 10.0.0.20 10.0.0.1")
private let thresholds = TunnelReducer.Thresholds(
    connectingDownGrace: 3,
    connectingTimeout: 30,
    connectedDownLimit: 2,
    networkTransitionLimit: 2
)

private struct SnapshotCase {
    let name: String
    let value: StatusSnapshot
}

private let snapshots = [
    SnapshotCase(name: "down", value: .down),
    SnapshotCase(name: "route-stale", value: .routeStale),
    SnapshotCase(name: "route-check-failed", value: .routeCheckFailed),
    SnapshotCase(name: "connecting", value: .connecting),
    SnapshotCase(name: "connected", value: .connected(ip: "10.8.0.42")),
    SnapshotCase(name: "config-error", value: .configError(missingFields: ["HOST", "GROUP"]))
]

private struct MatrixExpected {
    let phase: TunnelState
    let downStreak: Int
    let networkTransitionStreak: Int
    let connectStart: Date?
    let fingerprint: Fingerprint?
    let effects: [TunnelReducer.Effect]

    var result: TunnelReducer.Result {
        TunnelReducer.Result(
            state: TunnelReducer.Context(
                phase: phase,
                downStreak: downStreak,
                networkTransitionStreak: networkTransitionStreak,
                connectStart: connectStart,
                connectionNetworkFingerprint: fingerprint
            ),
            effects: effects
        )
    }
}

private func expected(
    _ phase: TunnelState,
    _ downStreak: Int,
    _ connectStart: Date?,
    _ fingerprint: Fingerprint?,
    _ effects: [TunnelReducer.Effect] = [],
    networkTransitionStreak: Int = 0
) -> MatrixExpected {
    MatrixExpected(
        phase: phase,
        downStreak: downStreak,
        networkTransitionStreak: networkTransitionStreak,
        connectStart: connectStart,
        fingerprint: fingerprint,
        effects: effects
    )
}

private struct MatrixRow {
    let name: String
    let input: TunnelReducer.Context
    let expected: [MatrixExpected]
}

// Literal expectations from issue #12/#19, the pre-refactor main.swift, and
// the network-transition debounce table from issue #23 (ADR-0003).
// The expected table never calls reducer helpers or mirrors its branches.
private let matrix: [MatrixRow] = [
    MatrixRow(
        name: "repairing",
        input: .init(phase: .repairing, downStreak: 0, networkTransitionStreak: 0, connectStart: nil, connectionNetworkFingerprint: nil),
        expected: [
            expected(.repairing, 0, nil, nil),
            expected(.repairing, 0, nil, nil),
            expected(.repairing, 0, nil, nil),
            expected(.repairing, 0, nil, nil),
            expected(.repairing, 0, nil, nil),
            expected(.disconnected, 0, nil, nil, [.recordMissingConfigFields(["HOST", "GROUP"])])
        ]
    ),
    MatrixRow(
        name: "disconnected",
        input: .init(phase: .disconnected, downStreak: 0, networkTransitionStreak: 0, connectStart: nil, connectionNetworkFingerprint: nil),
        expected: [
            expected(.disconnected, 0, nil, nil),
            expected(.disconnecting, 0, nil, nil, [.stopTunnel(after: .disconnected)]),
            expected(.errRoute, 0, nil, nil),
            expected(.connecting, 0, now, nil),
            expected(.connected, 0, nil, nil, [.captureFingerprint]),
            expected(.disconnected, 0, nil, nil, [.recordMissingConfigFields(["HOST", "GROUP"])])
        ]
    ),
    MatrixRow(
        name: "connecting",
        input: .init(phase: .connecting, downStreak: 0, networkTransitionStreak: 0, connectStart: connectStart, connectionNetworkFingerprint: baseline),
        expected: [
            expected(.connecting, 0, connectStart, baseline),
            expected(.disconnecting, 0, connectStart, baseline, [.stopTunnel(after: .errNetworkChanged)]),
            expected(.errRoute, 0, connectStart, baseline),
            expected(.connecting, 0, connectStart, baseline),
            expected(.connected, 0, connectStart, baseline, [.captureFingerprint]),
            expected(.disconnected, 0, connectStart, baseline, [.recordMissingConfigFields(["HOST", "GROUP"])])
        ]
    ),
    MatrixRow(
        name: "disconnecting",
        input: .init(phase: .disconnecting, downStreak: 0, networkTransitionStreak: 0, connectStart: nil, connectionNetworkFingerprint: nil),
        expected: [
            expected(.disconnecting, 0, nil, nil),
            expected(.disconnecting, 0, nil, nil),
            expected(.disconnecting, 0, nil, nil),
            expected(.disconnecting, 0, nil, nil),
            expected(.disconnecting, 0, nil, nil),
            expected(.disconnected, 0, nil, nil, [.recordMissingConfigFields(["HOST", "GROUP"])])
        ]
    ),
    MatrixRow(
        name: "connected",
        input: .init(phase: .connected, downStreak: 0, networkTransitionStreak: 0, connectStart: connectStart, connectionNetworkFingerprint: baseline),
        expected: [
            expected(.connected, 1, connectStart, baseline),
            expected(.disconnecting, 0, connectStart, baseline, [.stopTunnel(after: .errNetworkChanged)]),
            expected(.errRoute, 0, connectStart, baseline),
            expected(.connected, 0, connectStart, baseline),
            expected(.connected, 0, connectStart, baseline),
            expected(.disconnected, 0, connectStart, baseline, [.recordMissingConfigFields(["HOST", "GROUP"])])
        ]
    ),
    MatrixRow(
        name: "err-timeout",
        input: .init(phase: .errTimeout, downStreak: 0, networkTransitionStreak: 0, connectStart: nil, connectionNetworkFingerprint: nil),
        expected: [
            expected(.errTimeout, 0, nil, nil),
            expected(.errTimeout, 0, nil, nil),
            expected(.errTimeout, 0, nil, nil),
            expected(.errTimeout, 0, nil, nil),
            expected(.errTimeout, 0, nil, nil),
            expected(.disconnected, 0, nil, nil, [.recordMissingConfigFields(["HOST", "GROUP"])])
        ]
    ),
    MatrixRow(
        name: "err-auth",
        input: .init(phase: .errAuth, downStreak: 0, networkTransitionStreak: 0, connectStart: nil, connectionNetworkFingerprint: nil),
        expected: [
            expected(.errAuth, 0, nil, nil),
            expected(.errAuth, 0, nil, nil),
            expected(.errAuth, 0, nil, nil),
            expected(.errAuth, 0, nil, nil),
            expected(.errAuth, 0, nil, nil),
            expected(.disconnected, 0, nil, nil, [.recordMissingConfigFields(["HOST", "GROUP"])])
        ]
    ),
    MatrixRow(
        name: "err-cert",
        input: .init(phase: .errCert, downStreak: 0, networkTransitionStreak: 0, connectStart: nil, connectionNetworkFingerprint: nil),
        expected: [
            expected(.errCert, 0, nil, nil),
            expected(.errCert, 0, nil, nil),
            expected(.errCert, 0, nil, nil),
            expected(.errCert, 0, nil, nil),
            expected(.errCert, 0, nil, nil),
            expected(.disconnected, 0, nil, nil, [.recordMissingConfigFields(["HOST", "GROUP"])])
        ]
    ),
    MatrixRow(
        name: "err-dropped",
        input: .init(phase: .errDropped, downStreak: 0, networkTransitionStreak: 0, connectStart: nil, connectionNetworkFingerprint: nil),
        expected: [
            expected(.errDropped, 0, nil, nil),
            expected(.errDropped, 0, nil, nil),
            expected(.errDropped, 0, nil, nil),
            expected(.errDropped, 0, nil, nil),
            expected(.errDropped, 0, nil, nil),
            expected(.disconnected, 0, nil, nil, [.recordMissingConfigFields(["HOST", "GROUP"])])
        ]
    ),
    MatrixRow(
        name: "err-route",
        input: .init(phase: .errRoute, downStreak: 0, networkTransitionStreak: 0, connectStart: nil, connectionNetworkFingerprint: nil),
        expected: [
            expected(.errRoute, 0, nil, nil),
            expected(.errRoute, 0, nil, nil),
            expected(.errRoute, 0, nil, nil),
            expected(.errRoute, 0, nil, nil),
            expected(.errRoute, 0, nil, nil),
            expected(.disconnected, 0, nil, nil, [.recordMissingConfigFields(["HOST", "GROUP"])])
        ]
    ),
    MatrixRow(
        name: "err-stop",
        input: .init(phase: .errStop, downStreak: 0, networkTransitionStreak: 0, connectStart: nil, connectionNetworkFingerprint: nil),
        expected: [
            expected(.errStop, 0, nil, nil),
            expected(.errStop, 0, nil, nil),
            expected(.errStop, 0, nil, nil),
            expected(.errStop, 0, nil, nil),
            expected(.errStop, 0, nil, nil),
            expected(.disconnected, 0, nil, nil, [.recordMissingConfigFields(["HOST", "GROUP"])])
        ]
    ),
    MatrixRow(
        name: "err-network-changed",
        input: .init(phase: .errNetworkChanged, downStreak: 0, networkTransitionStreak: 0, connectStart: nil, connectionNetworkFingerprint: nil),
        expected: [
            expected(.errNetworkChanged, 0, nil, nil),
            expected(.errNetworkChanged, 0, nil, nil),
            expected(.errNetworkChanged, 0, nil, nil),
            expected(.errNetworkChanged, 0, nil, nil),
            expected(.errNetworkChanged, 0, nil, nil),
            expected(.disconnected, 0, nil, nil, [.recordMissingConfigFields(["HOST", "GROUP"])])
        ]
    )
]

print("== TunnelReducer 12 x 6 transition matrix ==")
check("matrix has 12 phases", 12, matrix.count)
check("matrix has 6 snapshots per phase", true, matrix.allSatisfy { $0.expected.count == 6 })

for row in matrix {
    for (index, snapshot) in snapshots.enumerated() {
        let actual = TunnelReducer.reduce(
            state: row.input,
            snapshot: snapshot.value,
            network: baseline,
            now: now,
            thresholds: thresholds
        )
        check("\(row.name) + \(snapshot.name)", row.expected[index].result, actual)
        matrixAssertions += 1
    }
}

private func reduce(
    _ state: TunnelReducer.Context,
    _ snapshot: StatusSnapshot?,
    network: Fingerprint? = baseline,
    at now: Date = now,
    thresholds: TunnelReducer.Thresholds = thresholds
) -> TunnelReducer.Result {
    TunnelReducer.reduce(state: state, snapshot: snapshot, network: network, now: now, thresholds: thresholds)
}

private func context(
    _ phase: TunnelState,
    downStreak: Int = 0,
    connectStart: Date? = connectStart,
    fingerprint: Fingerprint? = baseline,
    networkTransitionStreak: Int = 0
) -> TunnelReducer.Context {
    .init(
        phase: phase,
        downStreak: downStreak,
        networkTransitionStreak: networkTransitionStreak,
        connectStart: connectStart,
        connectionNetworkFingerprint: fingerprint
    )
}

print("\n== TunnelReducer timing, debounce, and network boundaries ==")

let firstDown = TunnelReducer.Result(state: context(.connected, downStreak: 1), effects: [])
check("connected first down is tolerated", firstDown, reduce(context(.connected), .down), boundary: true)

let secondDown = TunnelReducer.Result(
    state: context(.disconnecting, downStreak: 0),
    effects: [.stopTunnel(after: .errDropped)]
)
check("connected second consecutive down is dropped", secondDown, reduce(context(.connected, downStreak: 1), .down), boundary: true)

let resetDown = TunnelReducer.Result(state: context(.connected, downStreak: 0), effects: [])
check("connected non-down resets the streak", resetDown, reduce(context(.connected, downStreak: 1), .connecting), boundary: true)

let limitThree = TunnelReducer.Thresholds(
    connectingDownGrace: 3,
    connectingTimeout: 30,
    connectedDownLimit: 3,
    networkTransitionLimit: 2
)
let secondOfThree = TunnelReducer.Result(state: context(.connected, downStreak: 2), effects: [])
check(
    "connected down limit is injected",
    secondOfThree,
    reduce(context(.connected, downStreak: 1), .down, thresholds: limitThree),
    boundary: true
)

let graceBoundary = context(.connecting, connectStart: Date(timeIntervalSince1970: 997))
let graceExpected = TunnelReducer.Result(state: graceBoundary, effects: [])
check("connecting down at exactly 3s is tolerated", graceExpected, reduce(graceBoundary, .down), boundary: true)

let pastGrace = context(.connecting, connectStart: Date(timeIntervalSince1970: 996.999))
let timeoutAfterDown = TunnelReducer.Result(
    state: context(.disconnecting, connectStart: Date(timeIntervalSince1970: 996.999)),
    effects: [.stopTunnel(after: .errTimeout)]
)
check("connecting down after 3s times out", timeoutAfterDown, reduce(pastGrace, .down), boundary: true)

let timeoutBoundary = context(.connecting, connectStart: Date(timeIntervalSince1970: 970))
let timeoutBoundaryExpected = TunnelReducer.Result(state: timeoutBoundary, effects: [])
check("connecting snapshot at exactly 30s is tolerated", timeoutBoundaryExpected, reduce(timeoutBoundary, .connecting), boundary: true)

let pastTimeout = context(.connecting, connectStart: Date(timeIntervalSince1970: 969.999))
let timeoutAfterThirty = TunnelReducer.Result(
    state: context(.disconnecting, connectStart: Date(timeIntervalSince1970: 969.999)),
    effects: [.stopTunnel(after: .errTimeout)]
)
check("connecting snapshot after 30s times out", timeoutAfterThirty, reduce(pastTimeout, .connecting), boundary: true)

let connectedAfterThirty = TunnelReducer.Result(
    state: context(.connected, connectStart: Date(timeIntervalSince1970: 969)),
    effects: [.captureFingerprint]
)
check(
    "connected snapshot wins after 30s",
    connectedAfterThirty,
    reduce(context(.connecting, connectStart: Date(timeIntervalSince1970: 969)), .connected(ip: "10.8.0.42")),
    boundary: true
)

let noClock = context(.connecting, connectStart: nil)
check("missing connect clock does not invent a timeout", TunnelReducer.Result(state: noClock, effects: []), reduce(noClock, .down), boundary: true)

let networkChanged = TunnelReducer.Result(
    state: context(.disconnecting, downStreak: 0),
    effects: [.stopTunnel(after: .errNetworkChanged)]
)
check(
    "changed fingerprint is a network-change error",
    networkChanged,
    reduce(context(.connected), .connected(ip: "10.8.0.42"), network: changedNetwork),
    boundary: true
)
check(
    "changed fingerprint in connecting is the same network-change error",
    networkChanged,
    reduce(context(.connecting), .connecting, network: changedNetwork),
    boundary: true
)

// 网络过渡防抖表 (issue #23): 单周期 nil 容忍,恢复=基线清零,连续两周期拆,确定不同立即拆。
let transitioning = TunnelReducer.Result(state: context(.connected, networkTransitionStreak: 1), effects: [])
check(
    "single nil network is a tolerated transition",
    transitioning,
    reduce(context(.connected), .connected(ip: "10.8.0.42"), network: nil),
    boundary: true
)
check(
    "connecting tolerates the same single nil transition",
    TunnelReducer.Result(state: context(.connecting, networkTransitionStreak: 1), effects: []),
    reduce(context(.connecting), .connecting, network: nil),
    boundary: true
)
check(
    "second consecutive nil tears down the tunnel",
    networkChanged,
    reduce(context(.connected, networkTransitionStreak: 1), .connected(ip: "10.8.0.42"), network: nil),
    boundary: true
)
check(
    "second consecutive nil in connecting tears down the tunnel",
    networkChanged,
    reduce(context(.connecting, networkTransitionStreak: 1), .connecting, network: nil),
    boundary: true
)
let recovered = TunnelReducer.Result(state: context(.connected), effects: [])
check(
    "recovered fingerprint equal to the baseline clears the streak",
    recovered,
    reduce(context(.connected, networkTransitionStreak: 1), .connected(ip: "10.8.0.42")),
    boundary: true
)
check(
    "nil transition is tolerated even when the status read also failed",
    transitioning,
    reduce(context(.connected), nil, network: nil),
    boundary: true
)
check(
    "second nil wins over the connecting timeout (network compare keeps priority)",
    TunnelReducer.Result(
        state: context(.disconnecting, connectStart: Date(timeIntervalSince1970: 969)),
        effects: [.stopTunnel(after: .errNetworkChanged)]
    ),
    reduce(context(.connecting, connectStart: Date(timeIntervalSince1970: 969), networkTransitionStreak: 1), nil, network: nil),
    boundary: true
)
check(
    "network transition limit is injected",
    TunnelReducer.Result(state: context(.connected, networkTransitionStreak: 1), effects: []),
    reduce(
        context(.connected),
        .connected(ip: "10.8.0.42"),
        network: nil,
        thresholds: TunnelReducer.Thresholds(
            connectingDownGrace: 3,
            connectingTimeout: 30,
            connectedDownLimit: 2,
            networkTransitionLimit: 3
        )
    ),
    boundary: true
)

// 防抖判定纯函数冻结表 (issue #23 AC): nil 走计数,恢复=基线清零,确定不同不防抖。
let transitionTable: [(name: String, network: Fingerprint?, streak: Int, limit: Int, expected: TunnelReducer.NetworkTransition)] = [
    (name: "first nil is a transition", network: nil, streak: 0, limit: 2, expected: .transitioning(streak: 1)),
    (name: "second consecutive nil within limit 2 changes", network: nil, streak: 1, limit: 2, expected: .changed),
    (name: "recovery equal to the baseline is steady", network: baseline, streak: 1, limit: 2, expected: .steady),
    (name: "differing fingerprint changes without debounce", network: changedNetwork, streak: 0, limit: 2, expected: .changed),
    (name: "differing fingerprint changes mid-transition", network: changedNetwork, streak: 1, limit: 2, expected: .changed),
    (name: "limit 3 tolerates the second nil", network: nil, streak: 1, limit: 3, expected: .transitioning(streak: 2)),
    (name: "limit 3 changes on the third nil", network: nil, streak: 2, limit: 3, expected: .changed)
]
for row in transitionTable {
    check(
        "networkTransition: \(row.name)",
        row.expected,
        TunnelReducer.networkTransition(baseline: baseline, network: row.network, streak: row.streak, limit: row.limit),
        boundary: true
    )
}
check("networkTransition table has 7 rows", 7, transitionTable.count)

let awaitingFingerprint = context(.connected, fingerprint: nil)
check(
    "missing baseline awaits capture",
    TunnelReducer.Result(state: awaitingFingerprint, effects: []),
    reduce(awaitingFingerprint, .connected(ip: "10.8.0.42"), network: nil),
    boundary: true
)

let configError = StatusSnapshot.configError(missingFields: ["USER"])
let unconfigured = TunnelReducer.Result(
    state: context(.disconnected, connectStart: connectStart, fingerprint: baseline),
    effects: [.recordMissingConfigFields(["USER"])]
)
check("config-error maps active state to unconfigured", unconfigured, reduce(context(.connecting), configError), boundary: true)

let configWinsOverMissingNetwork = TunnelReducer.Result(
    state: context(.disconnected, connectStart: connectStart, fingerprint: baseline),
    effects: [.recordMissingConfigFields(["USER"])]
)
check(
    "config-error remains unconfigured when the network is unavailable",
    configWinsOverMissingNetwork,
    reduce(context(.connected), configError, network: nil),
    boundary: true
)

let routeWins = TunnelReducer.Result(
    state: context(.errRoute, connectStart: Date(timeIntervalSince1970: 969)),
    effects: []
)
check(
    "route failure wins over the 30s timeout",
    routeWins,
    reduce(context(.connecting, connectStart: Date(timeIntervalSince1970: 969)), .routeCheckFailed),
    boundary: true
)

let unavailableConnected = TunnelReducer.Result(
    state: context(.connected, downStreak: 0),
    effects: []
)
check(
    "status read failure resets connected debounce without migrating",
    unavailableConnected,
    reduce(context(.connected, downStreak: 1), nil),
    boundary: true
)

let unavailableTimeout = TunnelReducer.Result(
    state: context(.disconnecting, connectStart: Date(timeIntervalSince1970: 969)),
    effects: [.stopTunnel(after: .errTimeout)]
)
check(
    "status read failure still observes connecting timeout",
    unavailableTimeout,
    reduce(context(.connecting, connectStart: Date(timeIntervalSince1970: 969)), nil),
    boundary: true
)

let unavailableDisconnected = context(.disconnected)
check(
    "status read failure leaves inactive phases unchanged",
    TunnelReducer.Result(state: unavailableDisconnected, effects: []),
    reduce(unavailableDisconnected, nil),
    boundary: true
)

let typedVocabulary: [TunnelReducer.Effect] = [
    .startConnect,
    .stopTunnel(after: .disconnected),
    .captureFingerprint,
    .alert(.openconnectMissing)
]
check("effect vocabulary is typed and equatable", 4, typedVocabulary.count, boundary: true)

check("all 72 matrix cells executed", 72, matrixAssertions)
check("all 35 boundary assertions executed", 35, boundaryAssertions)

if failures > 0 {
    print("\n\(failures) failed")
    exit(1)
}
print("\n72 matrix cells + \(boundaryAssertions) boundary assertions passed")
