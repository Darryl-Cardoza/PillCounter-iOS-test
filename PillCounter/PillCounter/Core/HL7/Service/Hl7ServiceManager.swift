//
//  Hl7ServiceManager.swift
//  PillCounter
//
//  Created by Bhushan Patil on 03/02/26.
//

import Foundation

final class Hl7ServiceManager {

    private let port: UInt16
    private let serviceName: String
    private let serviceType: String

    private let advertiser = BonjourAdvertiser()
    private let server: HL7TLSServer

    var listener: Hl7EventListener?
    
    

    init(
        port: UInt16,
        serviceName: String,
        serviceType: String,
        listener: Hl7EventListener
    ) {
        self.port = port
        self.serviceName = serviceName
        self.serviceType = serviceType
        self.server = HL7TLSServer(port: port)
        self.listener = listener
    }

    // MARK: - Lifecycle

    func start() {
        do {
            listener?.onServiceStarted()
            try server.start(
                serviceName: serviceName,
                serviceType: serviceType,
                onMessage: { [weak self] raw, messageId in
                    print("🔔 onMessage callback FIRED")
                    print("🔍 self is nil: \(self == nil)")
                    print("🔍 self?.listener is nil: \(self?.listener == nil)")
                    
                    if let strongSelf = self {
                        print("✅ self exists, calling listener")
                        strongSelf.listener?.onMessageReceived(
                            raw: raw,
                            messageId: messageId
                        )
                    } else {
                        print("❌ self is nil in callback")
                    }
                },
                onAckSent: { [weak self] messageId in
                    print("🔔 onAckSent callback FIRED")
                    self?.listener?.onAckSent(messageId: messageId)
                }
            )
            listener?.onServerStarted(port: Int(port))
            listener?.onBonjourRegistered(serviceName: serviceName)

        } catch {
            listener?.onError(source: "Hl7ServiceManager.start", error: error)
        }
    }

    func stop() {
        advertiser.stop()
        server.stop()

        listener?.onServerStopped()
        listener?.onServiceStopped()
    }
}
