//
//  Hl7EventListener.swift
//  PillCounter
//
//  Created by Bhushan Patil on 03/02/26.
//

import Foundation
import ComposeApp

protocol Hl7EventListener: AnyObject {

    func onServiceStarted()
    func onServiceStopped()

    func onServerStarted(port: Int)
    func onServerStopped()

    func onMessageReceived(
        message: CompleteHL7Message,
        messageId: String
    )

    func onAckSent(messageId: String)

    func onError(source: String, error: Error)

    func onBonjourRegistered(serviceName: String)
    
    func onClientConnected()
    
    func onClientDisconnected()
    
    func onAckReceived(messageId: String? , ackCode: String)
}
