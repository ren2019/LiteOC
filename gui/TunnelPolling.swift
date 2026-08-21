import Foundation

struct TunnelPollSample: Equatable {
    let snapshot: StatusSnapshot?
    let network: Fingerprint?
    let clearsMissingConfigFields: Bool
    let keychainService: String?

    init(
        snapshot: StatusSnapshot?,
        network: Fingerprint?,
        clearsMissingConfigFields: Bool,
        keychainService: String? = nil
    ) {
        self.snapshot = snapshot
        self.network = network
        self.clearsMissingConfigFields = clearsMissingConfigFields
        self.keychainService = keychainService
    }
}

/// Runs one background read at a time and only delivers the newest generation.
final class BackgroundReadCoordinator<Value> {
    typealias Reader = () -> Value
    typealias Delivery = (Value) -> Void

    private let workerQueue: DispatchQueue
    private var generation: UInt64 = 0
    private var inFlight = false

    init(workerQueue: DispatchQueue) {
        self.workerQueue = workerQueue
    }

    @discardableResult
    func request(read: @escaping Reader, deliver: @escaping Delivery) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !inFlight else { return false }

        inFlight = true
        let requestGeneration = generation
        workerQueue.async { [weak self] in
            let sample = read()
            DispatchQueue.main.async {
                guard let self, self.generation == requestGeneration else { return }
                self.inFlight = false
                deliver(sample)
            }
        }
        return true
    }

    func invalidate() {
        dispatchPrecondition(condition: .onQueue(.main))
        generation &+= 1
        inFlight = false
    }
}

typealias TunnelPoller = BackgroundReadCoordinator<TunnelPollSample>
