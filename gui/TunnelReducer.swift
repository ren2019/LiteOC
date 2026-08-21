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
        case repairTunnel
        case readConnectionNetwork
        case startConnect
        case stopTunnel(after: TunnelState)
        case captureFingerprint
        case persistCertificate(String)
        case refreshStatus
        case showSettings(focusPin: Bool)
        case recordMissingConfigFields([String])
        case clearMissingConfigFields
        case alert(Alert)
    }

    enum NetworkRead: Equatable {
        case available(Fingerprint)
        case unavailable
        case configError(missingFields: [String])
        case failed
    }

    enum Event: Equatable {
        case launch(profileConfigured: Bool)
        case repairCompleted(RepairResult)
        case repairFailed
        case connectRequested(profileConfigured: Bool, pinAvailable: Bool)
        case connectionNetworkRead(NetworkRead)
        case startCompleted(StartResult)
        case startFailed
        case disconnectRequested(after: TunnelState)
        case stopCompleted(StopResult, after: TunnelState)
        case stopFailed
        case fingerprintRead(NetworkRead)
    }

    struct Result: Equatable {
        let state: Context
        let effects: [Effect]
    }

    static func reduce(state: Context, event: Event, now: Date) -> Result {
        func context(
            _ phase: TunnelState,
            connectStart: Date? = state.connectStart,
            fingerprint: Fingerprint? = state.connectionNetworkFingerprint
        ) -> Context {
            Context(
                phase: phase,
                downStreak: 0,
                connectStart: connectStart,
                connectionNetworkFingerprint: fingerprint
            )
        }

        func missing(_ fields: [String]) -> Result {
            Result(
                state: context(.disconnected),
                effects: [.recordMissingConfigFields(fields)]
            )
        }

        func networkChange() -> Result {
            Result(
                state: context(.disconnecting),
                effects: [.stopTunnel(after: .errNetworkChanged)]
            )
        }

        switch event {
        case let .launch(profileConfigured):
            guard profileConfigured else {
                return Result(state: context(.disconnected), effects: [])
            }
            return Result(state: context(.repairing), effects: [.repairTunnel])

        case let .repairCompleted(result):
            switch result {
            case .alreadyRunning, .repaired, .clean:
                return Result(
                    state: context(.disconnected),
                    effects: [.clearMissingConfigFields, .refreshStatus]
                )
            case .routeFailure:
                return Result(state: context(.errRoute), effects: [])
            case let .configError(missingFields):
                return missing(missingFields)
            }

        case .repairFailed:
            return Result(state: context(.errRoute), effects: [])

        case let .connectRequested(profileConfigured, pinAvailable):
            if state.phase == .connecting { return Result(state: state, effects: []) }
            guard profileConfigured else {
                return Result(
                    state: context(.disconnected),
                    effects: [.showSettings(focusPin: false)]
                )
            }
            guard pinAvailable else {
                return Result(
                    state: context(.disconnected),
                    effects: [.showSettings(focusPin: true)]
                )
            }
            return Result(state: state, effects: [.readConnectionNetwork])

        case let .connectionNetworkRead(result):
            switch result {
            case let .available(fingerprint):
                return Result(
                    state: context(.connecting, connectStart: now, fingerprint: fingerprint),
                    effects: [.startConnect]
                )
            case .unavailable:
                return Result(state: context(.errNetworkChanged), effects: [])
            case let .configError(missingFields):
                return missing(missingFields)
            case .failed:
                return Result(state: context(.errRoute), effects: [])
            }

        case let .startCompleted(result):
            let certificateEffects: [Effect]
            if case let .started(discoveredCert?) = result {
                certificateEffects = [.persistCertificate(discoveredCert)]
            } else {
                certificateEffects = []
            }
            guard state.phase == .connecting else {
                return Result(state: state, effects: certificateEffects)
            }
            switch result {
            case .started:
                var effects = certificateEffects
                effects.append(.clearMissingConfigFields)
                return Result(state: state, effects: effects)
            case .alreadyRunning, .stopTimeout:
                return Result(state: state, effects: [.clearMissingConfigFields])
            case .authenticationFailed:
                return Result(state: context(.errAuth), effects: [])
            case .certificateDiscoveryFailed:
                return Result(state: context(.errCert), effects: [])
            case .openconnectMissing:
                return Result(
                    state: context(.disconnected),
                    effects: [.alert(.openconnectMissing)]
                )
            case .noPin:
                return Result(state: context(.disconnected), effects: [])
            case .routeFailure:
                return Result(state: context(.errRoute), effects: [])
            case let .configError(missingFields):
                return missing(missingFields)
            }

        case .startFailed:
            return Result(state: state, effects: [])

        case let .disconnectRequested(successState):
            if state.phase == .disconnecting { return Result(state: state, effects: []) }
            return Result(
                state: context(.disconnecting),
                effects: [.stopTunnel(after: successState)]
            )

        case let .stopCompleted(result, successState):
            switch result {
            case .stopped:
                return Result(
                    state: context(successState, fingerprint: nil),
                    effects: [.clearMissingConfigFields]
                )
            case .stopTimeout:
                return Result(state: context(.errStop, fingerprint: nil), effects: [])
            case .routeFailure:
                return Result(state: context(.errRoute, fingerprint: nil), effects: [])
            case let .configError(missingFields):
                return Result(
                    state: context(.disconnected, fingerprint: nil),
                    effects: [.recordMissingConfigFields(missingFields)]
                )
            }

        case .stopFailed:
            return Result(state: context(.errRoute, fingerprint: nil), effects: [])

        case let .fingerprintRead(result):
            switch result {
            case let .available(fingerprint):
                return Result(
                    state: context(state.phase, fingerprint: fingerprint),
                    effects: []
                )
            case .unavailable, .failed:
                return networkChange()
            case let .configError(missingFields):
                return missing(missingFields)
            }
        }
    }

    static func reduce(
        state: Context,
        snapshot: StatusSnapshot?,
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

        if case let .configError(missingFields)? = snapshot {
            return Result(
                state: context(.disconnected),
                effects: [.recordMissingConfigFields(missingFields)]
            )
        }

        let monitorsNetwork = state.phase == .connecting || state.phase == .connected
        if monitorsNetwork,
           let baseline = state.connectionNetworkFingerprint,
           network != Optional(baseline) {
            return stop(after: .errNetworkChanged)
        }

        guard let snapshot else {
            switch state.phase {
            case .connecting:
                if let startedAt = state.connectStart,
                   now.timeIntervalSince(startedAt) > thresholds.connectingTimeout {
                    return stop(after: .errTimeout)
                }
            case .connected:
                return Result(state: context(.connected), effects: [])
            case .repairing, .disconnected, .disconnecting, .errTimeout, .errAuth,
                 .errCert, .errDropped, .errRoute, .errStop, .errNetworkChanged:
                break
            }
            return Result(state: state, effects: [])
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
