import Testing
import Foundation
@testable import PillCounter

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let (status, data) = handler(request)
        guard let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                              httpVersion: nil, headerFields: nil) else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func stubSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: config)
}

private func samplePayload() -> RemoteLogPayload {
    RemoteLogPayload(
        deviceKey: "d", appName: "PillCounter", appVersion: "1", platform: "iOS", osVersion: "17",
        deviceModel: "iPhone15,3", sessionId: "s", logId: "l", severity: 4,
        timestamp: "2026-09-28T00:00:00.000Z", message: "m", tag: "t", event: "UNKNOWN_ERROR",
        context: nil, error: nil, network: .init(type: "wifi", isOnline: true)
    )
}

struct RemoteLogHTTPClientTests {
    @Test func sendDoesNotThrowOnNon2xxResponse() async {
        StubURLProtocol.handler = { _ in (500, Data()) }
        let client = RemoteLogHTTPClient(session: stubSession())
        client.send(samplePayload())
        // Fire-and-forget: nothing to await; this test's success is that it
        // returns immediately without throwing/crashing.
    }

    @Test func sendDoesNotThrowOnTransportFailure() async {
        let brokenSession = URLSession(configuration: {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [] // no handler registered -> load fails
            return config
        }())
        let client = RemoteLogHTTPClient(session: brokenSession)
        client.send(samplePayload())
    }
}
