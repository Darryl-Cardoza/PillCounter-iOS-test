//
//  BarcodeFormatParserTests.swift
//  PillCounterTests
//

import Testing
@testable import PillCounter

@Suite
struct BarcodeFormatParserTests {

    private let format = #"^(?<rxnumber>[^|]{1,32})\|(?<refillno>\d{1,3})\|(?<ndc>\d{11})\|(?<qty>[\d.]{1,10})\|(?<bucket>[^|]{1,16})$"#

    // MARK: matches

    @Test func matchesFullValue() {
        #expect(BarcodeFormatParser.matches("RX100697|0|05278113375|30|340B", format: format))
    }

    @Test func matchesValueWithDashedNdc() {
        #expect(BarcodeFormatParser.matches("RX100697|0|0527-8113-37|30|340B", format: format))
    }

    @Test func doesNotMatchMissingRequiredField() {
        // refillno is required by this format (no "?" in the server pattern) — dropping it must fail.
        #expect(!BarcodeFormatParser.matches("RX100697|05278113375|30|340B", format: format))
    }

    @Test func doesNotMatchWrongDelimiter() {
        #expect(!BarcodeFormatParser.matches("RX100697-0-05278113375-30-340B", format: format))
    }

    @Test func matchesEmptyOptionalFieldWhenServerPatternAllowsIt() {
        // Server pattern itself marks bucket optional here — trailing "|" + empty segment allowed.
        let optionalBucketFormat = #"^(?<rxnumber>[^|]{1,32})\|(?<refillno>\d{1,3})\|(?<ndc>\d{11})\|(?<qty>[\d.]{1,10})(?:\|(?<bucket>[^|]{1,16}))?$"#
        #expect(BarcodeFormatParser.matches("RX100697|0|05278113375|30", format: optionalBucketFormat))
    }

    @Test func matchesFailsOnEmptyFormat() {
        #expect(!BarcodeFormatParser.matches("RX100697|0|05278113375|30|340B", format: ""))
    }

    @Test func matchesFailsOnInvalidRegexFormat() {
        #expect(!BarcodeFormatParser.matches("anything", format: "(unclosed"))
    }

    // MARK: mappedData

    @Test func mappedDataExtractsAllFields() throws {
        let mapped = try BarcodeFormatParser.mappedData(format: format, actualValue: "RX100697|0|05278113375|30|340B")
        #expect(mapped["RXNO"] == "RX100697")
        #expect(mapped["REFILLNO"] == "0")
        #expect(mapped["NDCNO"] == "05278113375")
        #expect(mapped["QTY"] == "30")
        #expect(mapped["BUCKET"] == "340B")
    }

    @Test func mappedDataStripsDashesFromNdc() throws {
        let mapped = try BarcodeFormatParser.mappedData(format: format, actualValue: "RX100697|0|0527-8113-37|30|340B")
        #expect(mapped["NDCNO"] == "0527811337")
    }

    @Test func mappedDataReturnsEmptyWhenValueDoesNotMatch() throws {
        let mapped = try BarcodeFormatParser.mappedData(format: format, actualValue: "garbage")
        #expect(mapped.isEmpty)
    }

    @Test func mappedDataReturnsEmptyForEmptyFormat() throws {
        let mapped = try BarcodeFormatParser.mappedData(format: "", actualValue: "RX100697|0|05278113375|30|340B")
        #expect(mapped.isEmpty)
    }

    @Test func mappedDataReturnsEmptyForEmptyValue() throws {
        let mapped = try BarcodeFormatParser.mappedData(format: format, actualValue: "")
        #expect(mapped.isEmpty)
    }

    @Test func mappedDataThrowsForInvalidRegexFormat() {
        #expect(throws: (any Error).self) {
            try BarcodeFormatParser.mappedData(format: "(unclosed", actualValue: "anything")
        }
    }

    // MARK: applyDashTolerance

    @Test func applyDashToleranceWidensNdcQuantifier() {
        let processed = BarcodeFormatParser.applyDashTolerance(to: format)
        #expect(processed.contains("(?<ndc>[\\d-]{11,13})"))
    }

    @Test func applyDashToleranceLeavesFormatWithoutNdcGroupUnchanged() {
        let noNdcFormat = #"^(?<rxnumber>[^|]{1,32})\|(?<qty>[\d.]{1,10})$"#
        #expect(BarcodeFormatParser.applyDashTolerance(to: noNdcFormat) == noNdcFormat)
    }
}
