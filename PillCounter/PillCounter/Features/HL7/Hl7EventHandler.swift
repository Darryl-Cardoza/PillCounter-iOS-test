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
        Log("Server started on port \(port)")
    }

    /// Called when HL7 server stops.
    func onHl7ServerStopped() {
        Log("Server stopped")
    }

    /// Called when Bonjour service is registered.
    func onBonjourRegistered(serviceName: String) {
        Log("Bonjour registered: \(serviceName)")
    }

    /// Called when a new HL7 message is received from PMS.
    func onMessageReceived(message: HL7Message, rawHl7: String) {
        Task { @MainActor in
            self.pillScanViewModel.handleReceivedMessage(
                message: message,
                rawHl7: rawHl7
            ) { _ in
                StoreLogger.debug("📥 [HL7] onMessageReceived: \(message)")
                self.userViewModel.getAllTransactionsAndFilterByCountType()
            }
        }
    }

    /// Called after ACK is sent to PMS.
    func onAckSent(messageId: String) {
        Log("ACK sent | id=\(messageId)")
    }

    /// Called when ACK is received from PMS.
    func onAckReceived(messageId: String?, ackCode: String, hl7:String) {
        Log("ACK received | id=\(messageId ?? "nil") code=\(ackCode)")

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
        Log("Client connected: \(serviceName)")

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
        Log("Client disconnected")
        Task { @MainActor in
            userViewModel.setPmsConnected(false)
        }
    }

    /// Called when any HL7-related error occurs.
    func onError(source: String, error: Error) {
        Log("Error | \(source) | \(error.localizedDescription)")
    }
}
