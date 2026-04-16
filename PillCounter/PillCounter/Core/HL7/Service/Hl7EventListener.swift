//
//  Hl7EventListener.swift
//  PillCounter
//
//  Created by Bhushan Patil on 03/02/26.
//

import Foundation
import ComposeApp

/// Listener for all HL7 lifecycle, messaging, and connection events.
protocol Hl7EventListener: AnyObject {

    /// Called when HL7 server starts listening on a given port.
    func onHL7ServerStarted(port: Int)

    /// Called when HL7 server is stopped.
    func onHl7ServerStopped()

    /// Called when a new HL7 message is received from PMS.
    func onMessageReceived(message: CompleteHL7Message)

    /// Called after an ACK is successfully sent to PMS.
    func onAckSent(messageId: String)

    /// Called when an ACK is received from PMS for a sent message.
    func onAckReceived(messageId: String?, ackCode: String)

    /// Called when any HL7-related error occurs.
    func onError(source: String, error: Error)

    /// Called when Bonjour service is registered for discovery.
    func onBonjourRegistered(serviceName: String)

    /// Called when connection to PMS client is established.
    func onClientConnected(serviceName: String)
    
    /// Called when connection to PMS client is lost.
    func onClientDisconnected()
}
