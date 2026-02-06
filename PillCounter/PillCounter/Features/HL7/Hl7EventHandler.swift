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

    func onServiceStarted() {
        print("HL7 service started")
    }

    func onServiceStopped() {
        print("HL7 service stopped")
    }

    func onServerStarted(port: Int) {
        print("HL7 server started on port \(port)")
    }

    func onServerStopped() {
        print("HL7 server stopped")
    }

    func onBonjourRegistered(serviceName: String) {
        print("Bonjour registered: \(serviceName)")
    }

    // MARK: - Incoming HL7 (Server side)

    func onMessageReceived(
        message: CompleteHL7Message,
        messageId: String
    ) {
        print("HL7 message received | id=\(messageId)")

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
        print("ACK sent | id=\(messageId)")
    }

    func onAckReceived(messageId: String) {
        print("ACK received | id=\(messageId)")
        Task { @MainActor in
            Hl7ServiceController.shared.onAckReceived(messageId: messageId)
        }
    }

    // MARK: - Client Events

    func onClientConnected() {
        print("HL7 client connected")
        Task { @MainActor in
            Hl7ServiceController.shared.onClientConnected()
        }
        
        HL7NotificationManager.show(
                  title: "PMS Connected",
                  body: "PillCounter is now connected to PMS"
              )

    }

    func onClientDisconnected() {
        print("HL7 client disconnected")
    }

    // MARK: - Error

    func onError(source: String, error: Error) {
        print("HL7 error | \(source) | \(error.localizedDescription)")
    }
}
