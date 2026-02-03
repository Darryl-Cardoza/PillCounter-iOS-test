//
//  Hl7EventHandler.swift
//  PillCounter
//
//  Created by Bhushan Patil on 03/02/26.
//

import Foundation

final class Hl7EventHandler: Hl7EventListener {
    
    let hl7Repository = Hl7Repository.shared

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

    func onMessageReceived(raw: String, messageId: String) {
        print("HL7 message received event| id=\(messageId)")
        hl7Repository.handleReceivedMessage(raw)
    }

    func onAckSent(messageId: String) {
        print("ACK sent | id=\(messageId)")
    }

    func onError(source: String, error: Error) {
        print("HL7 error | \(source) | \(error.localizedDescription)")
    }
}
