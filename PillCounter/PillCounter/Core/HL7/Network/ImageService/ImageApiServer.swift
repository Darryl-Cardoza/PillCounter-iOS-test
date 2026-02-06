//
//  ImageApiServer.swift
//  PillCounter
//
//  Created by Bhushan Patil on 06/02/26.
//

import Foundation
import GCDWebServer

final class ImageApiServer {

    static let shared = LocalApiServer()

    private let webServer = GCDWebServer()
    private let db = PillsDataLocalStorage.shared

    private init() {}

    // MARK: - Start / Stop

    func start(port: UInt = 8080) {
        guard !webServer.isRunning else { return }

        registerRoutes()

        try? webServer.start(
            options: [
                GCDWebServerOption_Port: port,
                GCDWebServerOption_BindToLocalhost: false,
                GCDWebServerOption_AutomaticallySuspendInBackground: false
            ]
        )

        print("🌐 Local API Server running at:", webServer.serverURL?.absoluteString ?? "")
    }

    func stop() {
        webServer.stop()
        print("🛑 Local API Server stopped")
    }
    
    private func registerRoutes() {

        // Health check
        webServer.addHandler(
            forMethod: "GET",
            path: "/health",
            request: GCDWebServerRequest.self
        ) { _ in
            return GCDWebServerDataResponse(json: [
                "status": "ok",
                "device": "iOS",
                "time": Date().timeIntervalSince1970
            ])
        }

        // GET all transactions
        webServer.addHandler(
            forMethod: "GET",
            path: "/transactions",
            request: GCDWebServerRequest.self
        ) { [weak self] _ in
            guard let self else {
                return GCDWebServerErrorResponse(statusCode: 500)
            }

            let txns = self.db.getAllTransactionsForApi()
            return GCDWebServerDataResponse(json: txns)
        }

        // GET single transaction
        webServer.addHandler(
            forMethod: "GET",
            pathRegex: "^/transactions/([0-9]+)$",
            request: GCDWebServerRequest.self
        ) { [weak self] request in
            guard
                let self,
                let txnId = Int64(request.pathComponents.last ?? "")
            else {
                return GCDWebServerErrorResponse(statusCode: 400)
            }

            guard let txn = self.db.getTransactionForApi(txnId: txnId) else {
                return GCDWebServerErrorResponse(statusCode: 404)
            }

            return GCDWebServerDataResponse(json: txn)
        }

        // GET transaction details
        webServer.addHandler(
            forMethod: "GET",
            pathRegex: "^/transactions/([0-9]+)/details$",
            request: GCDWebServerRequest.self
        ) { [weak self] request in
            guard
                let self,
                let txnId = Int64(request.pathComponents.dropLast().last ?? "")
            else {
                return GCDWebServerErrorResponse(statusCode: 400)
            }

            let details = self.db.getTransactionDetailsForApi(txnId: txnId)
            return GCDWebServerDataResponse(json: details)
        }
    }

}
