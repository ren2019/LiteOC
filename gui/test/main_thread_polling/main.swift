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

private func waitUntil(timeout: TimeInterval, _ condition: @escaping () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline && !condition() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.005))
    }
    return condition()
}

@main
enum MainThreadPollingTests {
    static func main() {
        print("== Main-thread polling contract ==")

        guard let testTemporaryPath = ProcessInfo.processInfo.environment["LITEOC_TEST_TMP"] else {
            print("FAIL LITEOC_TEST_TMP is required")
            exit(1)
        }
        let fakeDirectory = URL(fileURLWithPath: testTemporaryPath, isDirectory: true)
            .appendingPathComponent("fake-helper", isDirectory: true)
        let fakeHelper = fakeDirectory.appendingPathComponent("slow-vpnctl")
        do {
            try FileManager.default.createDirectory(at: fakeDirectory, withIntermediateDirectories: true)
            try "#!/bin/sh\nsleep 0.20\necho down\n".write(to: fakeHelper, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeHelper.path)
        } catch {
            print("FAIL create slow fake helper: \(error)")
            exit(1)
        }
        let slowClient = VpnctlClient(
            vpnctlPath: fakeHelper.path,
            configPath: "/tmp/liteoc-unused-config",
            sudoPath: "/usr/bin/env"
        )

        var heartbeat = false
        var delivered = false
        var deliveryObservedHeartbeat = false
        var deliveryRanOnMain = false
        var readerRanOnMain = true
        let responsivenessPoller = TunnelPoller(
            workerQueue: DispatchQueue(label: "test.poll.slow-reader")
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            heartbeat = true
        }
        let submittedAt = Date()
        let accepted = responsivenessPoller.request(
            read: {
                readerRanOnMain = Thread.isMainThread
                let snapshot = try? slowClient.status()
                return TunnelPollSample(snapshot: snapshot, network: nil, clearsMissingConfigFields: true)
            },
            deliver: { _ in
                deliveryRanOnMain = Thread.isMainThread
                deliveryObservedHeartbeat = heartbeat
                delivered = true
            }
        )
        let submissionDuration = Date().timeIntervalSince(submittedAt)

        check("slow helper read is accepted", true, accepted)
        check("request returns before the slow helper completes", true, submissionDuration < 0.05)
        check("slow helper eventually delivers", true, waitUntil(timeout: 1.0) { delivered })
        check("slow helper runs off the main thread", false, readerRanOnMain)
        check("result is delivered on the main thread", true, deliveryRanOnMain)
        check("main run loop stays responsive before delivery", true, deliveryObservedHeartbeat)

        let overlapLock = NSLock()
        var overlapReads = 0
        var overlapDelivered = false
        let overlapPoller = TunnelPoller(
            workerQueue: DispatchQueue(label: "test.poll.in-flight")
        )
        let firstAccepted = overlapPoller.request(
            read: {
                overlapLock.lock(); overlapReads += 1; overlapLock.unlock()
                Thread.sleep(forTimeInterval: 0.10)
                return TunnelPollSample(snapshot: .connecting, network: nil, clearsMissingConfigFields: true)
            },
            deliver: { _ in overlapDelivered = true }
        )
        let duplicateAccepted = overlapPoller.request(
            read: {
                overlapLock.lock(); overlapReads += 1; overlapLock.unlock()
                return TunnelPollSample(snapshot: .down, network: nil, clearsMissingConfigFields: true)
            },
            deliver: { _ in }
        )
        check("first in-flight poll is accepted", true, firstAccepted)
        check("overlapping poll is coalesced", false, duplicateAccepted)
        check("coalesced poll completes", true, waitUntil(timeout: 1.0) { overlapDelivered })
        overlapLock.lock(); let finalOverlapReads = overlapReads; overlapLock.unlock()
        check("coalescing performs one helper read", 1, finalOverlapReads)

        let oldStarted = DispatchSemaphore(value: 0)
        let releaseOld = DispatchSemaphore(value: 0)
        var deliveredSnapshots: [StatusSnapshot?] = []
        let epochPoller = TunnelPoller(
            workerQueue: DispatchQueue(label: "test.poll.epoch")
        )
        check(
            "old generation starts",
            true,
            epochPoller.request(
                read: {
                    oldStarted.signal()
                    _ = releaseOld.wait(timeout: .now() + 1.0)
                    return TunnelPollSample(snapshot: .connected(ip: "10.0.0.1"), network: nil, clearsMissingConfigFields: true)
                },
                deliver: { deliveredSnapshots.append($0.snapshot) }
            )
        )
        check("old generation reaches the slow helper", .success, oldStarted.wait(timeout: .now() + 1.0))
        epochPoller.invalidate()
        check(
            "new generation can be scheduled while the stale read drains",
            true,
            epochPoller.request(
                read: {
                    TunnelPollSample(snapshot: .down, network: nil, clearsMissingConfigFields: true)
                },
                deliver: { deliveredSnapshots.append($0.snapshot) }
            )
        )
        releaseOld.signal()
        check("new generation is delivered", true, waitUntil(timeout: 1.0) { deliveredSnapshots.count == 1 })
        check("late old generation is discarded", [StatusSnapshot?.some(.down)], deliveredSnapshots)

        let controlStarted = DispatchSemaphore(value: 0)
        let releaseControl = DispatchSemaphore(value: 0)
        let controlQueue = DispatchQueue(label: "test.control.long-running")
        controlQueue.async {
            controlStarted.signal()
            _ = releaseControl.wait(timeout: .now() + 1.0)
        }
        check("long control task starts", .success, controlStarted.wait(timeout: .now() + 1.0))
        let independentPoller = TunnelPoller(
            workerQueue: DispatchQueue(label: "test.poll.independent-from-control")
        )
        var independentDelivered = false
        check(
            "poll beside a busy control queue is accepted",
            true,
            independentPoller.request(
                read: { TunnelPollSample(snapshot: .connecting, network: nil, clearsMissingConfigFields: true) },
                deliver: { _ in independentDelivered = true }
            )
        )
        check(
            "busy control queue does not delay timeout sampling",
            true,
            waitUntil(timeout: 0.20) { independentDelivered }
        )
        check("control task is still occupied when poll arrives", .timedOut, releaseControl.wait(timeout: .now()))
        releaseControl.signal()

        let networkLock = NSLock()
        var networkReads = 0
        var networkDelivered = false
        var networkReaderRanOnMain = true
        var networkDeliveryRanOnMain = false
        let networkReader = BackgroundReadCoordinator<String>(
            workerQueue: DispatchQueue(label: "test.network.single-flight")
        )
        check(
            "first network effect is accepted",
            true,
            networkReader.request(
                read: {
                    networkReaderRanOnMain = Thread.isMainThread
                    networkLock.lock(); networkReads += 1; networkLock.unlock()
                    Thread.sleep(forTimeInterval: 0.10)
                    return "network-current"
                },
                deliver: { _ in
                    networkDeliveryRanOnMain = Thread.isMainThread
                    networkDelivered = true
                }
            )
        )
        check(
            "duplicate network effect is coalesced",
            false,
            networkReader.request(read: { "network-duplicate" }, deliver: { _ in })
        )
        check("single network effect completes", true, waitUntil(timeout: 1.0) { networkDelivered })
        check("network effect reads off the main thread", false, networkReaderRanOnMain)
        check("network effect delivers on the main thread", true, networkDeliveryRanOnMain)
        networkLock.lock(); let finalNetworkReads = networkReads; networkLock.unlock()
        check("coalesced network effect reads once", 1, finalNetworkReads)

        let staleNetworkStarted = DispatchSemaphore(value: 0)
        let releaseStaleNetwork = DispatchSemaphore(value: 0)
        var savedGenerationDeliveries: [String] = []
        let savedGenerationReader = BackgroundReadCoordinator<String>(
            workerQueue: DispatchQueue(label: "test.network.config-save")
        )
        check(
            "pre-save network read starts",
            true,
            savedGenerationReader.request(
                read: {
                    staleNetworkStarted.signal()
                    _ = releaseStaleNetwork.wait(timeout: .now() + 1.0)
                    return "old-config"
                },
                deliver: { savedGenerationDeliveries.append($0) }
            )
        )
        check(
            "pre-save network read reaches helper",
            .success,
            staleNetworkStarted.wait(timeout: .now() + 1.0)
        )
        savedGenerationReader.invalidate()
        check(
            "post-save network read is accepted while stale read drains",
            true,
            savedGenerationReader.request(
                read: { "saved-config" },
                deliver: { savedGenerationDeliveries.append($0) }
            )
        )
        releaseStaleNetwork.signal()
        check(
            "post-save generation is delivered",
            true,
            waitUntil(timeout: 1.0) { savedGenerationDeliveries.count == 1 }
        )
        check("pre-save late result is discarded", ["saved-config"], savedGenerationDeliveries)

        if assertions == 30 {
            print("  ok   all polling assertions executed")
        } else {
            failures += 1
            print("  FAIL all polling assertions executed\n       expected: 30\n       actual:   \(assertions)")
        }

        if failures > 0 {
            print("\n\(failures) failed")
            exit(1)
        }
        print("\n\(assertions) polling assertions passed")
    }
}
