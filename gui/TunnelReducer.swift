import Foundation

enum TunnelReducer {
    struct Context: Equatable {
        let phase: TunnelState
        let downStreak: Int
        let connectStart: Date?
        let connectionNetworkFingerprint: Fingerprint?
    }

    struct Thresholds: Equatable {
        let connectingDownGrace: TimeInterval
        let connectingTimeout: TimeInterval
        let connectedDownLimit: Int
    }

    enum Alert: Equatable {
        case openconnectMissing
    }

    enum Effect: Equatable {
        case startConnect
        case stopTunnel(after: TunnelState)
        case captureFingerprint
        case alert(Alert)
    }

    struct Result: Equatable {
        let state: Context
        let effects: [Effect]
    }

    static func reduce(
        state: Context,
        snapshot: StatusSnapshot,
        network: Fingerprint?,
        now: Date,
        thresholds: Thresholds
    ) -> Result {
        func context(_ phase: TunnelState, downStreak: Int = 0, connectStart: Date? = state.connectStart) -> Context {
            Context(
                phase: phase,
                downStreak: downStreak,
                connectStart: connectStart,
                connectionNetworkFingerprint: state.connectionNetworkFingerprint
            )
        }

        func stop(after phase: TunnelState) -> Result {
            Result(state: context(.disconnecting), effects: [.stopTunnel(after: phase)])
        }

        if case .configError = snapshot {
            return Result(state: context(.disconnected), effects: [])
        }

        let monitorsNetwork = state.phase == .connecting || state.phase == .connected
        if monitorsNetwork,
           let baseline = state.connectionNetworkFingerprint,
           network != Optional(baseline) {
            return stop(after: .errNetworkChanged)
        }

        if snapshot == .routeCheckFailed,
           state.phase == .disconnected || state.phase == .connecting || state.phase == .connected {
            return Result(state: context(.errRoute), effects: [])
        }

        switch state.phase {
        case .disconnected:
            switch snapshot {
            case .routeStale:
                return stop(after: .disconnected)
            case .connecting:
                return Result(state: context(.connecting, connectStart: now), effects: [])
            case .connected:
                return Result(state: context(.connected), effects: [.captureFingerprint])
            case .down, .routeCheckFailed, .configError:
                return Result(state: state, effects: [])
            }

        case .connecting:
            switch snapshot {
            case .connected:
                return Result(state: context(.connected), effects: [.captureFingerprint])
            case .routeStale:
                return stop(after: .errNetworkChanged)
            case .configError:
                return Result(state: context(.disconnected), effects: [])
            case .down:
                if let startedAt = state.connectStart,
                   now.timeIntervalSince(startedAt) > thresholds.connectingDownGrace {
                    return stop(after: .errTimeout)
                }
            case .connecting:
                if let startedAt = state.connectStart,
                   now.timeIntervalSince(startedAt) > thresholds.connectingTimeout {
                    return stop(after: .errTimeout)
                }
            case .routeCheckFailed:
                break
            }
            return Result(state: state, effects: [])

        case .connected:
            switch snapshot {
            case .routeStale:
                return stop(after: .errNetworkChanged)
            case .configError:
                return Result(state: context(.disconnected), effects: [])
            case .down:
                let nextStreak = state.downStreak + 1
                if nextStreak >= thresholds.connectedDownLimit {
                    return stop(after: .errDropped)
                }
                return Result(state: context(.connected, downStreak: nextStreak), effects: [])
            case .connecting, .connected:
                return Result(state: context(.connected), effects: [])
            case .routeCheckFailed:
                break
            }
            return Result(state: state, effects: [])

        case .repairing, .disconnecting, .errTimeout, .errAuth, .errCert,
             .errDropped, .errRoute, .errStop, .errNetworkChanged:
            return Result(state: state, effects: [])
        }
    }
}
