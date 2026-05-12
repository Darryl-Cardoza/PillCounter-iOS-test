

import Network

/// Discovers Bonjour services and resolves them to host + port.
final class BonjourServiceDiscovery {

    /// Background queue for browsing and resolving services.
    private let queue = DispatchQueue(label: "com.pillcounter.discovery")

    /// NWBrowser used to discover Bonjour services.
    private var browser: NWBrowser?

    /// Prevents resolving multiple services repeatedly.
    private var didResolve = false

    /// Callback when a service is resolved with host, port, and name.
    var onServiceResolved: ((String, Int, String) -> Void)?

    /// Starts browsing for Bonjour services of a given type.
    func startBrowsing(serviceType: String) {
        guard browser == nil else { return }

        // Create TCP parameters and allow peer-to-peer discovery
        let params = NWParameters.tcp
        params.includePeerToPeer = true

        // Initialize browser for Bonjour service type
        browser = NWBrowser(
            for: .bonjour(type: serviceType, domain: nil),
            using: params
        )

        // Observe browser state changes
        browser?.stateUpdateHandler = { state in
            Log("Browser state: \(state)")
        }

        // Called when available services change
        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self, !self.didResolve else { return }

            // Iterate through discovered services
            for result in results {

                // Extract service name from endpoint
                guard case let .service(name, _, _, _) = result.endpoint else {
                    continue
                }

                // Resolve only first discovered service
                self.didResolve = true
                self.resolve(result, serviceName: name)
                break
            }
        }

        // Start browsing on background queue
        browser?.start(queue: queue)
    }

    /// Stops browsing and resets state.
    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        didResolve = false
    }

    // MARK: - Resolve Service

    /// Resolves a Bonjour service into host and port.
    private func resolve(_ result: NWBrowser.Result, serviceName: String) {

        // Endpoint contains connection details for the service
        let endpoint = result.endpoint

        // Create temporary connection to resolve endpoint
        let connection = NWConnection(to: endpoint, using: .tcp)

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }

            switch state {

            case .ready:
                // Extract resolved host and port
                if case let .hostPort(host, port) = connection.currentPath?.remoteEndpoint {
                    Log("Resolved \(serviceName) → \(host):\(port)")

                    self.onServiceResolved?(
                        host.debugDescription,
                        Int(port.rawValue),
                        serviceName
                    )

                    // Close temporary connection after resolving
                    connection.cancel()
                }

            case .failed(let error):
                // Handle resolution failure
                Log("Service resolve failed: \(error.localizedDescription)")
                connection.cancel()

            default:
                break
            }
        }

        // Start connection to trigger resolution
        connection.start(queue: queue)
    }
}
