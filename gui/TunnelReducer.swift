import Foundation

enum TunnelReducer {
    struct Context: Equatable {
        let phase: TunnelState
        let downStreak: Int
        var networkTransitionStreak: Int
        let connectStart: Date?
        let connectionNetworkFingerprint: Fingerprint?
        var reconnectAttempts = 0
        var userInitiated = false
        var reconnectSession = false
    }

    struct Thresholds: Equatable {
        let connectingDownGrace: TimeInterval
        let connectingTimeout: TimeInterval
        let connectedDownLimit: Int
        let networkTransitionLimit: Int
        var reconnectAttemptLimit = 3
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

    enum NetworkTransition: Equatable {
        case steady
        case transitioning(streak: Int)
        case changed
    }

    // 重连会话中的一次失败尝试 (issue #24 / ADR-0003): 配额内再拆一轮继续,配额尽转终红。
    static func reconnectAttemptFailed(state: Context, limit: Int) -> Result {
        let attempts = state.reconnectAttempts + 1
        let exhausted = attempts >= limit
        return Result(
            state: Context(
                phase: .disconnecting,
                downStreak: 0,
                networkTransitionStreak: 0,
                connectStart: state.connectStart,
                connectionNetworkFingerprint: state.connectionNetworkFingerprint,
                reconnectAttempts: attempts,
                userInitiated: state.userInitiated,
                reconnectSession: !exhausted
            ),
            effects: [.stopTunnel(after: exhausted ? .errReconnectFailed : .reconnecting)]
        )
    }

    // 判变拆隧道的共享 teardown,快照/事件两入口共用 (issue #25 / ADR-0003):
    // 用户会话转 Reconnecting——connecting 途中判变时在飞的连接尝试计为一次失败
    // ("初次失败计入 3 次配额"),connected 后判变无在飞尝试、计数清零 (issue #24);
    // 启动残留 (非用户会话) 维持旧终态红。
    static func networkChangeTeardown(state: Context) -> Result {
        guard state.userInitiated else {
            return Result(
                state: Context(
                    phase: .disconnecting,
                    downStreak: 0,
                    networkTransitionStreak: 0,
                    connectStart: state.connectStart,
                    connectionNetworkFingerprint: state.connectionNetworkFingerprint,
                    reconnectAttempts: state.reconnectAttempts,
                    userInitiated: state.userInitiated,
                    reconnectSession: state.reconnectSession
                ),
                effects: [.stopTunnel(after: .errNetworkChanged)]
            )
        }
        return Result(
            state: Context(
                phase: .disconnecting,
                downStreak: 0,
                networkTransitionStreak: 0,
                connectStart: nil,
                connectionNetworkFingerprint: state.connectionNetworkFingerprint,
                reconnectAttempts: state.phase == .connecting ? state.reconnectAttempts + 1 : 0,
                userInitiated: state.userInitiated,
                reconnectSession: state.reconnectSession
            ),
            effects: [.stopTunnel(after: .reconnecting)]
        )
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

    // 网络过渡防抖 (issue #23 / ADR-0003): 取不到指纹是过渡态,连续 limit 个周期才判变化;
    // 读到确定不同(非 nil 且不等于基线)不防抖。
    static func networkTransition(
        baseline: Fingerprint,
        network: Fingerprint?,
        streak: Int,
        limit: Int
    ) -> NetworkTransition {
        guard let network else {
            let next = streak + 1
            return next >= limit ? .changed : .transitioning(streak: next)
        }
        if network == baseline { return .steady }
        return .changed
    }

    static func reduce(state: Context, event: Event, now: Date, thresholds: Thresholds) -> Result {
        func context(
            _ phase: TunnelState,
            connectStart: Date? = state.connectStart,
            fingerprint: Fingerprint? = state.connectionNetworkFingerprint,
            networkTransitionStreak: Int = 0,
            reconnectAttempts: Int = state.reconnectAttempts,
            userInitiated: Bool = state.userInitiated,
            reconnectSession: Bool = state.reconnectSession
        ) -> Context {
            Context(
                phase: phase,
                downStreak: 0,
                networkTransitionStreak: networkTransitionStreak,
                connectStart: connectStart,
                connectionNetworkFingerprint: fingerprint,
                reconnectAttempts: reconnectAttempts,
                userInitiated: userInitiated,
                reconnectSession: reconnectSession
            )
        }

        func missing(_ fields: [String]) -> Result {
            Result(
                state: context(.disconnected),
                effects: [.recordMissingConfigFields(fields)]
            )
        }

        // 确认网络变化: 两入口共用同一份判变 teardown (issue #25)。
        func networkChange() -> Result {
            networkChangeTeardown(state: state)
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
            if state.phase == .connecting || state.phase == .reconnecting {
                return Result(state: state, effects: [])
            }
            guard profileConfigured else {
                return Result(
                    state: context(.disconnected, connectStart: nil),
                    effects: [.showSettings(focusPin: false)]
                )
            }
            guard pinAvailable else {
                return Result(
                    state: context(.disconnected, connectStart: nil),
                    effects: [.showSettings(focusPin: true)]
                )
            }
            return Result(
                state: Context(
                    phase: state.phase,
                    downStreak: 0,
                    networkTransitionStreak: 0,
                    connectStart: state.connectStart,
                    connectionNetworkFingerprint: state.connectionNetworkFingerprint,
                    reconnectAttempts: 0,
                    userInitiated: true,
                    reconnectSession: false
                ),
                effects: [.readConnectionNetwork]
            )

        case let .connectionNetworkRead(result):
            switch result {
            case let .available(fingerprint):
                return Result(
                    state: context(.connecting, connectStart: now, fingerprint: fingerprint),
                    effects: [.startConnect]
                )
            case .unavailable:
                // 重连等待网络: 保持黄灯不计数,由周期轮询驱动下一轮读 (issue #24)。
                if state.phase == .reconnecting { return Result(state: state, effects: []) }
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
                // 重连途中 PIN 失效: 立即红,重试无意义 (issue #24)。
                return Result(state: context(.errAuth, reconnectSession: false), effects: [])
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
                if state.reconnectSession { return reconnectAttemptFailed(state: state, limit: thresholds.reconnectAttemptLimit) }
                return Result(state: context(.errRoute), effects: [])
            case let .configError(missingFields):
                return missing(missingFields)
            }

        case .startFailed:
            if state.phase == .connecting, state.reconnectSession {
                return reconnectAttemptFailed(state: state, limit: thresholds.reconnectAttemptLimit)
            }
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
                // 拆完进入重连会话: 清基线,发起新一轮"指纹先读、有基线再连"链 (issue #24)。
                if successState == .reconnecting {
                    return Result(
                        state: context(
                            .reconnecting,
                            connectStart: nil,
                            fingerprint: nil,
                            reconnectSession: true
                        ),
                        effects: [.clearMissingConfigFields, .readConnectionNetwork]
                    )
                }
                return Result(
                    state: context(successState, fingerprint: nil, reconnectSession: false),
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
            let read: Fingerprint?
            switch result {
            case let .available(fingerprint):
                read = fingerprint
            case .unavailable, .failed:
                read = nil
            case let .configError(missingFields):
                return missing(missingFields)
            }
            guard let baseline = state.connectionNetworkFingerprint else {
                if let read {
                    return Result(state: context(state.phase, fingerprint: read), effects: [])
                }
                return networkChange()
            }
            switch networkTransition(
                baseline: baseline,
                network: read,
                streak: state.networkTransitionStreak,
                limit: thresholds.networkTransitionLimit
            ) {
            case .changed:
                return networkChange()
            case .steady:
                return Result(state: context(state.phase, fingerprint: read), effects: [])
            case let .transitioning(streak):
                return Result(state: context(state.phase, networkTransitionStreak: streak), effects: [])
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
        var state = state
        func context(
            _ phase: TunnelState,
            downStreak: Int = 0,
            connectStart: Date? = state.connectStart,
            networkTransitionStreak: Int = 0,
            reconnectAttempts: Int = state.reconnectAttempts,
            userInitiated: Bool = state.userInitiated,
            reconnectSession: Bool = state.reconnectSession
        ) -> Context {
            Context(
                phase: phase,
                downStreak: downStreak,
                networkTransitionStreak: networkTransitionStreak,
                connectStart: connectStart,
                connectionNetworkFingerprint: state.connectionNetworkFingerprint,
                reconnectAttempts: reconnectAttempts,
                userInitiated: userInitiated,
                reconnectSession: reconnectSession
            )
        }

        func stop(after phase: TunnelState) -> Result {
            // 重连会话中的连接超时算一次失败尝试,配额内继续拆隧道重试 (issue #24)。
            if phase == .errTimeout, state.reconnectSession {
                return reconnectAttemptFailed(state: state, limit: thresholds.reconnectAttemptLimit)
            }
            return Result(state: context(.disconnecting), effects: [.stopTunnel(after: phase)])
        }

        if case let .configError(missingFields)? = snapshot {
            return Result(
                state: context(.disconnected),
                effects: [.recordMissingConfigFields(missingFields)]
            )
        }

        // 过渡态指纹 (nil) 防抖: 网络瞬断不立即拆隧道,连续 limit 个周期才判变化 (issue #23)。
        // 过渡中直接返回 (不动作); 确定不同立即拆; 恢复=基线时计数清零后继续正常快照归约。
        let monitorsNetwork = state.phase == .connecting || state.phase == .connected
        if monitorsNetwork,
           let baseline = state.connectionNetworkFingerprint {
            switch networkTransition(
                baseline: baseline,
                network: network,
                streak: state.networkTransitionStreak,
                limit: thresholds.networkTransitionLimit
            ) {
            case .changed:
                // 用户会话转自动重连;启动残留维持旧终态红 (issue #24 / #25)。
                if state.userInitiated {
                    return networkChangeTeardown(state: state)
                }
                return stop(after: .errNetworkChanged)
            case let .transitioning(nextStreak):
                return Result(
                    state: context(
                        state.phase,
                        downStreak: state.downStreak,
                        networkTransitionStreak: nextStreak
                    ),
                    effects: []
                )
            case .steady:
                state.networkTransitionStreak = 0
            }
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
            case .repairing, .disconnected, .disconnecting, .reconnecting, .errTimeout, .errAuth,
                 .errCert, .errDropped, .errRoute, .errStop, .errNetworkChanged, .errReconnectFailed:
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
                return Result(state: context(.disconnecting), effects: [.stopTunnel(after: .disconnected)])
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

        case .reconnecting:
            // 等待网络由周期 tick 驱动重读(选 tick 而非 effect 自循环: 单一计时器节奏可测,断网期间自然限频)。
            return Result(state: state, effects: [.readConnectionNetwork])

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
             .errDropped, .errRoute, .errStop, .errNetworkChanged, .errReconnectFailed:
            return Result(state: state, effects: [])
        }
    }
}
