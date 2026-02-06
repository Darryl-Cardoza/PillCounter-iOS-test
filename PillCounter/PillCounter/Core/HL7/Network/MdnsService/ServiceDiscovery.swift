import Network


import Network

final class ServiceDiscovery {

    private let queue = DispatchQueue(label: "com.pillcounter.discovery")
    private var browser: NWBrowser?
    private var didResolve = false

    var onServiceResolved: ((String, Int, String) -> Void)?

    func startBrowsing(serviceType: String) {
        guard browser == nil else { return }

        let params = NWParameters.tcp
        params.includePeerToPeer = true

        browser = NWBrowser(
            for: .bonjour(type: serviceType, domain: nil),
            using: params
        )

        browser?.stateUpdateHandler = { state in
            print("Browser state:", state)
        }

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self, !self.didResolve else { return }

            for result in results {
                guard case let .service(name, _, _, _) = result.endpoint else {
                    continue
                }

                self.didResolve = true
                self.resolve(result, serviceName: name)
                break
            }
        }

        browser?.start(queue: queue)
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        didResolve = false
    }

    // MARK: - Correct resolution

    private func resolve(_ result: NWBrowser.Result, serviceName: String) {

        // The endpoint already knows how to connect
        let endpoint = result.endpoint

        let connection = NWConnection(to: endpoint, using: .tcp)

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }

            switch state {
            case .ready:
                if case let .hostPort(host, port) = connection.currentPath?.remoteEndpoint {
                    print("Resolved service \(serviceName) → \(host):\(port)")
                    self.onServiceResolved?(
                        host.debugDescription,
                        Int(port.rawValue),
                        serviceName
                    )
                    connection.cancel()
                }

            case .failed(let error):
                print("Service resolve failed:", error)
                connection.cancel()

            default:
                break
            }
        }

        connection.start(queue: queue)
    }
}
