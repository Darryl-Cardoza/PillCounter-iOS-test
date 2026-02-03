import Network

final class ServiceDiscovery {

    private let queue = DispatchQueue(label: "com.pillcounter.discovery")
    private var browser: NWBrowser?

    var onServiceResolved: ((String, Int, String) -> Void)?

    func startBrowsing(serviceType: String) {
        guard browser == nil else { return }

        let params = NWParameters.tcp
        params.includePeerToPeer = true

        browser = NWBrowser(
            for: .bonjour(type: serviceType, domain: "local"),
            using: params
        )

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            for result in results {
                guard case let .service(name, _, _, _) = result.endpoint else { continue }
                self?.resolve(result.endpoint, name: name)
            }
        }

        browser?.start(queue: queue)
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
    }

    private func resolve(_ endpoint: NWEndpoint, name: String) {
        let connection = NWConnection(to: endpoint, using: .tcp)

        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state,
               case let .hostPort(host, port) = connection.endpoint {
                self?.onServiceResolved?("\(host)", Int(port.rawValue), name)
            }
            connection.cancel()
        }

        connection.start(queue: queue)
    }
}
