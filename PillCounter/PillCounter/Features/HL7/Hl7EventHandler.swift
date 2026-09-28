import Hl7Core

/// Handles HL7 events and bridges them to ViewModels and controllers.
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


    /// Called when HL7 server starts listening.
    func onHL7ServerStarted(port: Int) {
        AppLogger.shared.info("Server started on port \(port)")
    }

    /// Called when HL7 server stops.
    func onHl7ServerStopped() {
        AppLogger.shared.info("Server stopped")
    }

    /// Called when Bonjour service is registered.
    func onBonjourRegistered(serviceName: String) {
        AppLogger.shared.info("Bonjour registered: \(serviceName)")
    }

    /// Called when a new HL7 message is received from PMS.
    func onMessageReceived(message: HL7Message, rawHl7: String) {
        Task { @MainActor in
            self.pillScanViewModel.handleReceivedMessage(
                message: message,
                rawHl7: rawHl7
            ) { _ in
                // The message body carries patient/drug PHI — log only identifying
                // metadata, never the message contents.
                StoreLogger.debug("📥 [HL7] onMessageReceived: type=\(message.messageType) controlId=\(message.messageControlId)")
                self.userViewModel.getAllTransactionsAndFilterByCountType()
            }
        }
    }

    /// Called after ACK is sent to PMS.
    func onAckSent(messageId: String) {
        AppLogger.shared.info("ACK sent | id=\(messageId)")
    }

    /// Called when ACK is received from PMS.
    func onAckReceived(messageId: String?, ackCode: String, hl7:String) {
        AppLogger.shared.info("ACK received | id=\(messageId ?? "nil") code=\(ackCode)")

        Task { @MainActor in
            Hl7ServiceController.shared.onAckReceived(
                messageId: messageId,
                ackCode: ackCode,
                hl7: hl7
            )
        }
    }

    /// Called when PMS client connects.
    func onClientConnected(serviceName: String) {
        AppLogger.shared.info("Client connected: \(serviceName)")

        Task { @MainActor in
            Hl7ServiceController.shared.onClientConnected()
            userViewModel.setPmsConnected(true)
        }

        HL7NotificationManager.show(
            title: L10n.PMS.connected,
            body: L10n.PMS.connectedBody(serviceName)
        )
    }

    /// Called when PMS client disconnects.
    func onClientDisconnected() {
        AppLogger.shared.info("Client disconnected")
        Task { @MainActor in
            userViewModel.setPmsConnected(false)
        }
    }

    /// Called when any HL7-related error occurs.
    func onError(source: String, error: Error) {
        AppLogger.shared.error("HL7 error | \(source)", error: error)
    }
}
