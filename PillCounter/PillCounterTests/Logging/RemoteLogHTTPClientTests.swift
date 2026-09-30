import Testing
import Foundation
@testable import PillCounter

private final class LogAPIStubProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var fail = false
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open(); defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            return data
        }
        if Self.fail {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func makeClient(serverKey: String = "test-key", accessToken: String = "test-token",
                        baseURL: String = "https://api.example.com") -> RemoteLogHTTPClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [LogAPIStubProtocol.self]
    return RemoteLogHTTPClient(session: URLSession(configuration: config),
                               baseURL: { baseURL }, serverKey: { serverKey }, accessToken: { accessToken })
}

@Suite(.serialized)
struct RemoteLogHTTPClientTests {
    init() {
        LogAPIStubProtocol.status = 200
        LogAPIStubProtocol.fail = false
        LogAPIStubProtocol.lastRequest = nil
        LogAPIStubProtocol.lastBody = nil
    }

    @Test func classifiesStatusCodes() {
        #expect(RemoteLogHTTPClient.classify(statusCode: 200) == .delivered)
        #expect(RemoteLogHTTPClient.classify(statusCode: 201) == .delivered)
        #expect(RemoteLogHTTPClient.classify(statusCode: 299) == .delivered)
        #expect(RemoteLogHTTPClient.classify(statusCode: 301) == .retry)
        #expect(RemoteLogHTTPClient.classify(statusCode: 400) == .drop)
        #expect(RemoteLogHTTPClient.classify(statusCode: 401) == .unauthorized)
        #expect(RemoteLogHTTPClient.classify(statusCode: 408) == .retry)
        #expect(RemoteLogHTTPClient.classify(statusCode: 422) == .drop)
        #expect(RemoteLogHTTPClient.classify(statusCode: 429) == .retry)
        #expect(RemoteLogHTTPClient.classify(statusCode: 500) == .retry)
        #expect(RemoteLogHTTPClient.classify(statusCode: 503) == .retry)
    }

    @Test func successfulPostIsDeliveredWithExpectedRequest() async {
        let body = Data("{\"log_id\":\"1\"}".utf8)
        let result = await makeClient().deliver(body)

        #expect(result == .delivered)
        let request = LogAPIStubProtocol.lastRequest
        #expect(request?.httpMethod == "POST")
        #expect(request?.url?.absoluteString == "https://api.example.com/mobile/logs")
        #expect(request?.value(forHTTPHeaderField: "X-Server-Key") == "test-key")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(request?.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(LogAPIStubProtocol.lastBody == body)
    }

    @Test func serverErrorIsRetryable() async {
        LogAPIStubProtocol.status = 503
        #expect(await makeClient().deliver(Data("{}".utf8)) == .retry)
    }

    @Test func throttleAndTimeoutStatusesAreRetryable() async {
        for status in [408, 429] {
            LogAPIStubProtocol.status = status
            #expect(await makeClient().deliver(Data("{}".utf8)) == .retry)
        }
    }

    @Test func badRequestIsDropped() async {
        LogAPIStubProtocol.status = 422
        #expect(await makeClient().deliver(Data("{}".utf8)) == .drop)
    }

    @Test func transportFailureIsRetryable() async {
        LogAPIStubProtocol.fail = true
        #expect(await makeClient().deliver(Data("{}".utf8)) == .retry)
    }

    @Test func emptyAccessTokenIsUnauthorizedAndNothingIsSent() async {
        let result = await makeClient(accessToken: "").deliver(Data("{}".utf8))
        #expect(result == .unauthorized)
        #expect(LogAPIStubProtocol.lastRequest == nil)
    }

    @Test func unauthorizedIsNotRetried() async {
        LogAPIStubProtocol.status = 401
        #expect(await makeClient().deliver(Data("{}".utf8)) == .unauthorized)
    }

    @Test func emptyServerKeyIsNotRetriedAndNothingIsSent() async {
        let result = await makeClient(serverKey: "").deliver(Data("{}".utf8))
        #expect(result == .unauthorized)
        #expect(LogAPIStubProtocol.lastRequest == nil)
    }
}
