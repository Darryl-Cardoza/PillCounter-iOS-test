import Testing
import Foundation
@testable import PillCounter

@Suite
struct ErrorTranslatorTests {
    @Test func translatesTimedOutURLError() {
        let message = ErrorTranslator.translate(URLError(.timedOut))
        #expect(message == "The request timed out while communicating with the server.")
    }

    @Test func translatesCannotConnectToHost() {
        let message = ErrorTranslator.translate(URLError(.cannotConnectToHost))
        #expect(message == "Unable to establish a connection with the server.")
    }

    @Test func translatesDecodingError() {
        struct Dummy: Decodable {}
        let underlying = DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "bad json")
        )
        #expect(ErrorTranslator.translate(underlying) == "The server response could not be understood.")
    }

    @Test func translatesAPIErrorUsingItsOwnLocalizedDescription() {
        let error = APIError.unauthorized
        #expect(ErrorTranslator.translate(error) == error.localizedDescription)
    }

    @Test func fallsBackToGenericMessageForUnknownError() {
        struct CustomError: Error {}
        #expect(ErrorTranslator.translate(CustomError()) == "An unexpected error occurred.")
    }
}
