//
//  LocalHttpServer.swift
//  PillCounter
//
//  Created by Bhushan Patil on 06/02/26.
//

import Foundation
import Network

final class LocalHttpServer {

    static let shared = LocalHttpServer()

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "local.http.server")

    private init() {}

    func start(port: UInt16 = 8080) {
        guard listener == nil else { return }

        do {
            listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            print("❌ Failed to start server:", error)
            return
        }

        listener?.newConnectionHandler = { connection in
            connection.start(queue: self.queue)
            self.receive(on: connection)
        }

        listener?.start(queue: queue)
        print("🌐 Local HTTP Server running on port \(port)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
            data, _, _, _ in

            guard let data,
                  let request = String(data: data, encoding: .utf8)
            else { return }

            let response = self.handle(request: request)
            connection.send(
                content: response,
                completion: .contentProcessed { _ in
                    connection.cancel()
                }
            )
        }
    }
}
