//
//  Hl7ServiceController.swift
//  PillCounter
//

import Foundation
import SwiftUI
import Combine
import Hl7Core

/// Narrow surface `UnsyncedViewModel.syncAll()` needs — lets it inject a mock
/// instead of reaching for `Hl7ServiceController.shared` directly.
@MainActor
protocol Hl7SyncTrigger: AnyObject {
    var isPMSConnected: Bool { get }
    func onClientConnected()
}

@MainActor
final class Hl7ServiceController: ObservableObject, Hl7SyncTrigger {

    static let shared = Hl7ServiceController()

    // MARK: - App Storage

    // selectedTerminalName is UserDefaults-backed — @AppStorage is valid here.
    @AppStorage(AppStorageManager.AppStorageKeys.selectedTerminalName)
    private var selectedTerminalName: String = ""

    // MARK: - Dependencies

    let transactionDAO = TransactionStore.shared
    let batchDAO = BatchStore.shared
    var cancellables = Set<AnyCancellable>()

    // MARK: - HL7 Layer
    var hl7Manager: Hl7ServiceManager?
    private var hl7Handler: Hl7EventHandler?

    // MARK: - Bind (called once from SwiftUI root)
    func bind(pillScanViewModel: PillScanViewModel, userViewModel: UserViewModel) {
        guard hl7Handler == nil else { return }
        hl7Handler = Hl7EventHandler(
            pillScanViewModel: pillScanViewModel,
            userViewModel: userViewModel
        )
    }

    // MARK: - Entry Point
    func evaluate() {
        guard shouldStartService else {
            stopService()
            return
        }
        startHl7Services()
        setupBatchSyncQueue()
        setupTxnSyncQueue()
        observeTxnChanges()
        observeBatchCompletion()
    }

    private var shouldStartService: Bool {
        AppStorageManager.shared.isLoggedIn
            && (AppStorageManager.shared.isPmsIntegrated || AppStorageManager.shared.isStandalone)
            && !SecurityManager.isDeviceCompromised()
    }

    // MARK: - Start / Stop

    private func startHl7Services() {
        guard hl7Manager == nil, let handler = hl7Handler else { return }

        let serviceName = selectedTerminalName.isEmpty ? "Terminal-1" : selectedTerminalName
        hl7Manager = Hl7ServiceManager(
            port: 2575,
            serviceName: serviceName,
            serviceType: AppStorageManager.shared.pillCounterHostName,
            pmsServiceType: AppStorageManager.shared.pmsHostName,
            listener: handler
        )
    }

    /// Call this after a terminal update so HL7 rebroadcasts with the new name.
    func restartForTerminalChange() {
        guard shouldStartService else { return }
        stopService()
        startHl7Services()
        setupBatchSyncQueue()
        setupTxnSyncQueue()
        observeTxnChanges()
        observeBatchCompletion()
    }

    /// Call this after loadMobileThemeSettings() successfully writes
    /// pmsHostName and pillCounterHostName to AppStorageManager.
    /// If the manager was created before settings arrived (empty service type),
    /// this triggers the first real Bonjour browse.
    func notifySettingsUpdated() {
        guard shouldStartService else { return }

        if hl7Manager == nil {
            // Manager wasn't created yet at all — start fresh now
            startHl7Services()
            setupBatchSyncQueue()
            setupTxnSyncQueue()
            observeTxnChanges()
            observeBatchCompletion()
        } else {
            // Manager exists but was stuck with an empty pmsServiceType —
            // pass the now-populated value so the browser can start.
            hl7Manager?.restartBrowsingIfNeeded(pmsServiceType: AppStorageManager.shared.pmsHostName)
        }
    }

    private func stopService() {
        hl7Manager?.stop()
        hl7Manager = nil
    }

    // MARK: - Observe Pending Transactions

    /// Background queue the stale-transaction sweep runs on — it's an
    /// unbounded Core Data fetch (see `sweepStaleSyncedTransactions`), and
    /// `transactionsDidChange` can fire once per transaction while the HL7
    /// sync queue drains a large backlog (one ACK = one save = one signal).
    /// Running it inline on `.sink` (main thread, once per signal) froze the
    /// UI for the duration of that fetch, up to thousands of times in a row.
    private let sweepQueue = DispatchQueue(label: "hl7.stale-sweep.queue", qos: .utility)

    private func observeTxnChanges() {
        transactionDAO.transactionsDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                AppLogger.shared.debug("[TxnObserver] Detected change → enqueue txn sync")
                self?.txnSyncQueue?.enqueueUnsynced()
            }
            .store(in: &cancellables)

        // Sweep is a maintenance backstop (see `sweepStaleSyncedTransactions`
        // doc comment), not something that needs to run on every single
        // change — throttled to at most once every `sweepThrottleInterval`
        // and moved off main, so a fast-draining sync queue (thousands of
        // ACKs in quick succession) doesn't run thousands of unbounded
        // fetches, let alone on the main thread.
        transactionDAO.transactionsDidChange
            .throttle(for: .seconds(Self.sweepThrottleInterval), scheduler: sweepQueue, latest: true)
            .sink { [weak self] in
                self?.transactionDAO.sweepStaleSyncedTransactions(olderThan: Self.retentionMaxAge)
            }
            .store(in: &cancellables)
    }

    private static let sweepThrottleInterval: TimeInterval = 30

    /// Backstop TTL for transactions whose PMS image delivery never
    /// completes — see TransactionStore.sweepStaleSyncedTransactions.
    private static let retentionMaxAge: TimeInterval = 24 * 60 * 60

    /// Source of truth for "can Sync All actually do anything right now" —
    /// `hl7Manager` is nil whenever `shouldStartService` was false at launch
    /// (not logged in / not PMS-integrated / device compromised), and even
    /// with a manager, sends are silently dropped unless the client
    /// connection is actually `.ready`. `UnsyncedViewModel.syncAll()` checks
    /// this before doing anything, so a disconnected tap surfaces `syncError`
    /// instead of silently no-oping.
    var isPMSConnected: Bool {
        hl7Manager?.isClientConnected ?? false
    }

    // MARK: - Events from Hl7EventHandler

    func onClientConnected() {
        AppLogger.shared.info("[HL7] onClientConnected — starting batch + txn queues")
        batchSyncQueue?.resetParkedState()
        txnSyncQueue?.resetParkedState()
        batchSyncQueue?.enqueueUnsynced()
        txnSyncQueue?.enqueueUnsynced()
        // Covers an item left at queue.first after a dropped send — enqueueUnsynced()
        // alone won't re-drive it since queue isn't empty.
        batchSyncQueue?.drainNow()
        txnSyncQueue?.drainNow()
    }

    func onAckReceived(messageId: String?, ackCode: String, hl7: String) {
        batchSyncQueue?.handleAck(messageId: messageId, hl7: hl7)
        txnSyncQueue?.handleAck(messageId: messageId, hl7: hl7)
    }

}
