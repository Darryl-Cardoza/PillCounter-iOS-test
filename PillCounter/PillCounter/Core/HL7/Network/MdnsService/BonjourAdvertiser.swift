//
//  BonjourAdvertiser.swift
//  PillCounter
//
//  Created by Bhushan Patil on 02/02/26.
//

import Foundation
import Network

final class BonjourAdvertiser {

    private var listener: NWListener?

    func startAdvertising(
        serviceName: String,
        serviceType: String,
        port: UInt16
    ) {
        do {
            let params = NWParameters.tcp
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

            listener.service = NWListener.Service(
                name: serviceName,
                type: serviceType,
                domain: "local"
            )

            listener.newConnectionHandler = { connection in
                print("Incoming connection from \(connection.endpoint)")
                connection.start(queue: .main)
            }

            listener.stateUpdateHandler = { state in    
                print("Advertiser state: \(state)")
            }

            listener.start(queue: .main)
            self.listener = listener
        } catch {
            print("Failed to advertise service: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }
}
