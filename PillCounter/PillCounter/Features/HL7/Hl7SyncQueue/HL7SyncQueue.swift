//
//  HL7SyncQueue.swift
//  PillCounter
//
//  Shared ACK-driven drain/send/retry machinery used by both
//  HL7TxnSyncQueue and HL7BatchSyncQueue. `processNext()` (payload building
//  + send) stays in each subclass — it differs too much per entity type
//  (different fetch signature, different builder method, different guard
//  conditions) to generalize without a heavier config-driven abstraction
//  that isn't worth it for two call sites.
//
//  Three behaviors are DELIBERATELY left as overridable hooks rather than
//  unified, because the two existing queues disagree on them today and this
//  refactor must not silently change behavior:
//   - `removeFirstQueueItem()`: HL7TxnSyncQueue does an unconditional
//     `queue.removeFirst()` (a latent crash risk on an empty queue);
//     HL7BatchSyncQueue guards with `if !queue.isEmpty`.
//   - `shouldSkipItem(_:)`: HL7TxnSyncQueue skips soft-deleted rows during
//     drain; HL7BatchSyncQueue has no equivalent skip.
//   - `handleNilPendingRequestId()`: HL7BatchSyncQueue's `processAck` resets
//     `isSending`/calls `processNext()` when `pendingRequestId` is nil;
//     HL7TxnSyncQueue's equivalent branch does neither, just returns.
//

import Foundation

protocol HL7QueueItem {
    var requestId: String { get }
    /// Keyset-pagination cursor (`created_at`/`start_date_time`) — avoids
    /// OFFSET pagination, which skips rows when `processAck` removes items
    /// from the result set mid-drain.
    var cursor: Int64 { get }
}

class HL7SyncQueue<Item: HL7QueueItem> {

    var queue: [Item] = []
    var isSending = false
    var pendingRequestId: String?
    /// MSH-10 (messageControlId) of the in-flight HL7 message — the PMS
    /// echoes this back in MSA-2, NOT `pendingRequestId` (an internal dedup
    /// key). ACKs must be matched against this.
    var pendingAckMessageId: String?

    /// requestIds that failed (NACK or ACK timeout) in the current
    /// connection session. Parked items are skipped by
    /// `loadAndEnqueuePending` until `resetParkedState()` runs.
    var parkedRequestIds: Set<String> = []

    private var ackTimeoutWork: DispatchWorkItem?

    let ackTimeoutSeconds: TimeInterval = 10
    let processingQueue: DispatchQueue

    /// Backlog-drain chunking: how many unsynced rows `loadAndEnqueuePending`
    /// fetches per hop, and how long it yields between chunks. A single
    /// unbounded fetch held the main `viewContext` continuously long enough,
    /// with a large backlog, to read as an app freeze while connecting.
    let loadChunkSize = 50
    let loadChunkDelay: TimeInterval = 0.05

    init(processingQueueLabel: String) {
        self.processingQueue = DispatchQueue(label: processingQueueLabel, qos: .utility)
    }

    // MARK: - Overridable hooks (subclass MUST/MAY override)

    /// Default: unconditional removeFirst — matches HL7TxnSyncQueue's
    /// current behavior. HL7BatchSyncQueue overrides to guard against empty.
    func removeFirstQueueItem() {
        queue.removeFirst()
    }

    /// Default: never skip — matches HL7BatchSyncQueue's current behavior.
    /// HL7TxnSyncQueue overrides to skip soft-deleted rows (done at the
    /// page-fetch call site, not here — see HL7TxnSyncQueue.enqueueUnsynced).
    func shouldSkipItem(_ item: Item) -> Bool {
        false
    }

    /// Default: no-op — matches HL7TxnSyncQueue's current behavior (its
    /// nil-`pendingRequestId` branch in `processAck` just returns).
    /// HL7BatchSyncQueue overrides to reset `isSending` and call
    /// `processNext()`.
    func handleNilPendingRequestId() {}

    /// Subclass MUST override — marks the item at `queue.first`'s
    /// underlying row synced (via its own store, on a background context).
    func markCurrentItemSynced() {
        fatalError("markCurrentItemSynced() must be overridden by \(type(of: self))")
    }

    /// Subclass MUST override — builds and sends the next queued item (or
    /// returns immediately if `isSending` or `queue` is empty). Called once
    /// after the first page loads, and again after every ACK/NACK/timeout
    /// via `advanceQueue()` to keep the drain going.
    func processNext() {
        fatalError("processNext() must be overridden by \(type(of: self))")
    }

    // MARK: - Public

    func resetParkedState() {
        processingQueue.async { [weak self] in
            self?.parkedRequestIds.removeAll()
        }
    }

    func handleAck(messageId: String?, hl7 ackMessage: String) {
        processingQueue.async { [weak self] in
            guard let self, self.pendingAckMessageId != nil, messageId == self.pendingAckMessageId else { return }
            self.processAck(ackMessage)
        }
    }

    // MARK: - Load / drain

    /// `fetchPage(after, limit)` — subclass-provided keyset page fetch (each
    /// queue's `fetchCompletedUnsyncedPage(after:limit:)`, already mapped to
    /// `Item`). `after` is `nil` for the first page, then the previous
    /// page's last `cursor`. `onFirstChunk` — called once, after the first
    /// chunk lands, so the subclass can kick off `processNext()` (which
    /// stays subclass-side).
    func loadAndEnqueuePending(after cursor: Int64?, fetchPage: @escaping (Int64?, Int) -> [Item], onFirstChunk: @escaping () -> Void) {
        if cursor == nil {
            guard queue.isEmpty else { return }
        }

        let page = fetchPage(cursor, loadChunkSize)

        for candidate in page {
            if shouldSkipItem(candidate) { continue }
            guard !parkedRequestIds.contains(candidate.requestId) else { continue }
            guard !queue.contains(where: { $0.requestId == candidate.requestId }) else { continue }
            queue.append(candidate)
        }

        if cursor == nil {
            onFirstChunk()
        }

        guard page.count == loadChunkSize, let lastCursor = page.last?.cursor else { return }

        processingQueue.asyncAfter(deadline: .now() + loadChunkDelay) { [weak self] in
            self?.loadAndEnqueuePending(after: lastCursor, fetchPage: fetchPage, onFirstChunk: onFirstChunk)
        }
    }

    // MARK: - ACK

    func isPositiveAck(_ message: String) -> Bool {
        message.contains("|AA|") || message.contains("|AA\r")
    }

    func processAck(_ message: String) {
        cancelAckTimeout()

        guard let requestId = pendingRequestId else {
            handleNilPendingRequestId()
            return
        }

        if isPositiveAck(message) {
            markCurrentItemSynced()
        } else {
            parkedRequestIds.insert(requestId)
        }
        advanceQueue()
    }

    func advanceQueue() {
        isSending = false
        pendingRequestId = nil
        pendingAckMessageId = nil
        removeFirstQueueItem()
        processNext()
    }

    // MARK: - Timeout

    func scheduleAckTimeout(for requestId: String) {
        let work = DispatchWorkItem { [weak self] in
            self?.processingQueue.async {
                guard let self, self.pendingRequestId == requestId else { return }
                self.parkedRequestIds.insert(requestId)
                self.advanceQueue()
            }
        }
        ackTimeoutWork = work
        DispatchQueue.global().asyncAfter(deadline: .now() + ackTimeoutSeconds, execute: work)
    }

    func cancelAckTimeout() {
        ackTimeoutWork?.cancel()
        ackTimeoutWork = nil
    }
}
