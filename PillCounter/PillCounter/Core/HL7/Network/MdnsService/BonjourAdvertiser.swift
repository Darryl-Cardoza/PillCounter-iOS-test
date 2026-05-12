//
//  BonjourAdvertiser.swift
//  PillCounter
//
//  Created by Bhushan Patil on 02/02/26.
//

import Foundation
import Network

/// Advertises the HL7 service over Bonjour for network discovery.
final class BonjourAdvertiser {

    /// NWListener instance used for advertising and accepting connections.
    private var listener: NWListener?

    /// Starts Bonjour advertising with given service name, type, and port.
    func startAdvertising(
        serviceName: String,
        serviceType: String,
        port: UInt16
    ) {
        do {
            // Create TCP parameters for the listener
            let params = NWParameters.tcp

            // Initialize listener on specified port
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                Log("Invalid port: \(port)")
                return
            }

            let listener = try NWListener(using: params, on: nwPort)
            
            // Configure Bonjour service details
            listener.service = NWListener.Service(
                name: serviceName,
                type: serviceType,
                domain: "local"
            )

            // Handle incoming connections (optional for advertisement use-case)
            listener.newConnectionHandler = { connection in
                Log("Incoming connection from \(connection.endpoint)")
                connection.start(queue: .main)
            }

            // Observe listener state changes ready, cancelled, failed etc
            listener.stateUpdateHandler = { state in
            }

            // Start advertising on main queue
            listener.start(queue: .main)

            // Retain listener instance
            self.listener = listener

        } catch {
            // Log failure to start advertising
            Log("Failed to advertise service: \(error)")
        }
    }

    /// Stops Bonjour advertising and cleans up resources.
    func stop() {
        listener?.cancel()
        listener = nil
    }
}
