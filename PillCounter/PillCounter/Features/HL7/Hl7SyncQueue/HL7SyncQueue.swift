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

    /// Items whose ACK timeout just fired, keyed by the `pendingAckMessageId`
    /// they were sent with — kept around briefly so a real AA that was
    /// already in flight and loses the race against `scheduleAckTimeout`
    /// (static-IP RTT is less predictable than local Bonjour LAN, so this
    /// isn't rare there) still marks the item synced instead of being
    /// silently dropped by `handleAck`'s now-stale `pendingAckMessageId`
    /// guard. Bounded to a handful of entries — cleared as each is either
    /// claimed by a late ACK or evicted by `resetParkedState()`.
    private var recentlyTimedOutByAckMessageId: [String: Item] = [:]

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

    /// Subclass MUST override — same write `markCurrentItemSynced()` does,
    /// but for a specific item rather than `queue.first`. Needed for a late
    /// ACK arriving after that item was already timed-out/removed from
    /// `queue` — see `recentlyTimedOutByAckMessageId`.
    func markItemSynced(_ item: Item) {
        fatalError("markItemSynced(_:) must be overridden by \(type(of: self))")
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
            // New session's resends carry new MSH-10s, so entries stashed
            // under the old session's messageIds can never be claimed by a
            // legit late ACK past this point — clear them too or they leak.
            self?.recentlyTimedOutByAckMessageId.removeAll()
        }
    }

    /// Re-drives the queue after a real reconnect — unlike `enqueueUnsynced()`,
    /// which skips its `processNext()` call whenever `queue` already has
    /// items. Unconditional; `processNext()` itself no-ops if already
    /// sending or the queue is empty, so this is safe to call anytime.
    func drainNow() {
        processingQueue.async { [weak self] in
            self?.processNext()
        }
    }

    func handleAck(messageId: String?, hl7 ackMessage: String) {
        processingQueue.async { [weak self] in
            guard let self else { return }

            if let messageId, self.pendingAckMessageId != nil, messageId == self.pendingAckMessageId {
                self.processAck(ackMessage)
                return
            }

            // Not the currently in-flight item — check whether this is a
            // real AA that arrived just after its own ACK timeout already
            // fired and moved the queue on without it (see
            // `recentlyTimedOutByAckMessageId`).
            if let messageId, let item = self.recentlyTimedOutByAckMessageId.removeValue(forKey: messageId) {
                if self.isPositiveAck(ackMessage) {
                    self.parkedRequestIds.remove(item.requestId)
                    self.markItemSynced(item)
                }
            }
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

    /// Called from `processNext()` when `sendHL7ToPMS` returns false (not
    /// connected — nothing was sent, no ACK will ever arrive). Resets
    /// in-flight state without calling `processNext()`: retrying immediately
    /// would just drop again while still disconnected. The item stays at
    /// `queue.first`; `Hl7ServiceController.onClientConnected()` re-drives it
    /// once the connection genuinely comes back.
    func handleSendDropped(requestId: String) {
        processingQueue.async { [weak self] in
            guard let self, self.pendingRequestId == requestId else { return }
            self.cancelAckTimeout()
            self.isSending = false
            self.pendingRequestId = nil
            self.pendingAckMessageId = nil
        }
    }

    // MARK: - Timeout

    func scheduleAckTimeout(for requestId: String) {
        let work = DispatchWorkItem { [weak self] in
            self?.processingQueue.async {
                guard let self, self.pendingRequestId == requestId else { return }
                // Stash the item under its ack messageId before advanceQueue()
                // removes it from `queue` — a real AA already in flight when
                // this timeout fired can still claim it via `handleAck`.
                if let ackMessageId = self.pendingAckMessageId, let item = self.queue.first {
                    self.recentlyTimedOutByAckMessageId[ackMessageId] = item
                }
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
