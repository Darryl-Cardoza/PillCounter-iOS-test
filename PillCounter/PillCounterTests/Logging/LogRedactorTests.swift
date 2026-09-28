import Testing
@testable import PillCounter

struct LogRedactorTests {
    @Test func masksEmailAddresses() {
        let result = LogRedactor.redact("contact pharmacist at jane.doe@example.com about refill")
        #expect(result == "contact pharmacist at [REDACTED_EMAIL] about refill")
    }

    @Test func masksSeparatedPhoneNumbers() {
        let result = LogRedactor.redact("callback number 415-555-0132 left")
        #expect(result?.contains("[REDACTED_PHONE]") == true)
        #expect(result?.contains("415-555-0132") == false)
    }

    @Test func masksNationalIdShapedDigits() {
        let result = LogRedactor.redact("SSN on file 123-45-6789")
        #expect(result?.contains("[REDACTED_ID]") == true)
    }

    @Test func masksLuhnValidCardNumbers() {
        // 4111111111111111 is a well-known Luhn-valid test Visa number.
        let result = LogRedactor.redact("card ending in 4111111111111111 declined")
        #expect(result?.contains("[REDACTED_CARD]") == true)
        #expect(result?.contains("4111111111111111") == false)
    }

    @Test func doesNotRedactBareLongNumericIdentifiers() {
        // NDC-shaped (not Luhn-valid, no separators) — must survive untouched.
        let ndc = "NDC 00069319071 mismatch for order 1234567890123456"
        #expect(LogRedactor.redact(ndc) == ndc)
    }

    @Test func passesThroughTextWithNoSensitiveData() {
        let plain = "Scan timed out after 3 attempts"
        #expect(LogRedactor.redact(plain) == plain)
    }

    @Test func returnsNilForNilInput() {
        #expect(LogRedactor.redact(nil) == nil)
    }
}
