//
//  Hl7EventListener.swift
//  PillCounter
//
//  Created by Bhushan Patil on 03/02/26.
//

import Foundation

protocol Hl7EventListener: AnyObject {
    
    

    func onServiceStarted()
    func onServiceStopped()

    func onServerStarted(port: Int)
    func onServerStopped()

    func onMessageReceived(
        raw: String,
        messageId: String
    )

    func onAckSent(messageId: String)

    func onError(source: String, error: Error)

    func onBonjourRegistered(serviceName: String)
}
