
import ComposeApp

final class Hl7EventHandler: Hl7EventListener {

    private let pillScanViewModel: PillScanViewModel
    private let userViewModel: UserViewModel

    init(
        pillScanViewModel: PillScanViewModel,
        userViewModel: UserViewModel
    ) {
        self.pillScanViewModel = pillScanViewModel
        self.userViewModel = userViewModel
    }

    // MARK: - Service Events

    func onServiceStarted() {
        print("[HL7] Service started")
    }

    func onServiceStopped() {
        print("[HL7] Service stopped")
    }

    func onServerStarted(port: Int) {
        print("[HL7] Server started on port \(port)")
    }

    func onServerStopped() {
        print("[HL7] Server stopped")
    }

    func onBonjourRegistered(serviceName: String) {
        print("[HL7] Bonjour registered: \(serviceName)")
    }

    // MARK: - Incoming HL7 (Server side — PMS → PillCounter)

    func onMessageReceived(
        message: CompleteHL7Message,
        messageId: String
    ) {
        print("[HL7] Message received | id=\(messageId)")

        Task { @MainActor in
            self.pillScanViewModel.handleReceivedMessage(
                message: message
            ) { _ in
                self.userViewModel.getAllTransactionsAndFilterByCountType()
            }
        }

        HL7NotificationManager.show(
            title: "HL7 Message Received",
            body: "New order received from PMS"
        )
    }

    // MARK: - ACK Events

    func onAckSent(messageId: String) {
        print("[HL7] ACK sent | id=\(messageId)")
    }

    func onAckReceived(messageId: String?, ackCode: String) {
        Task { @MainActor in
            Hl7ServiceController.shared.onAckReceived(
                messageId: messageId,
                ackCode: ackCode
            )
        }
    }

    // MARK: - Client Events

    func onClientConnected() {
        print("[HL7] Client connected")

        Task { @MainActor in
            Hl7ServiceController.shared.onClientConnected()
            userViewModel.setPmsConnected(true)
        }

        HL7NotificationManager.show(
            title: "PMS Connected",
            body: "PillCounter is now connected to PMS"
        )
    }

    func onClientDisconnected() {
        print("[HL7] Client disconnected")

        Task { @MainActor in
            userViewModel.setPmsConnected(false)
        }
        // NOTE: No controller call needed here.
        // Hl7ServiceManager keeps the browser alive and will auto-reconnect.
    }

    // MARK: - Error

    func onError(source: String, error: Error) {
        print("[HL7] Error | \(source) | \(error.localizedDescription)")
    }
}
