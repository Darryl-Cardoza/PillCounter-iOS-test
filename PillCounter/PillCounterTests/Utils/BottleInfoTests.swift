//
//  BottleInfoTests.swift
//  PillCounterTests
//

import Testing
@testable import PillCounter

@Suite
struct BottleInfoTests {

    @Test func roundTripEncodeDecodeSingleBottle() throws {
        let bottle = BottleInfo(
            lotNumber: "LOT123",
            expirationDate: "12-31-2026",
            serialNumber: "SN456",
            txnDetailsIds: [1, 2, 3],
            scannedAt: 1_700_000_000_000
        )
        let json = try #require([bottle].encodedJson())
        let decoded = [BottleInfo].decode(from: json)
        #expect(decoded == [bottle])
    }

    @Test func roundTripEncodeDecodeMultipleBottles() throws {
        let bottles = [
            BottleInfo(lotNumber: "L1", expirationDate: "01-01-2027", serialNumber: "S1", txnDetailsIds: [10], scannedAt: 1),
            BottleInfo(lotNumber: nil, expirationDate: nil, serialNumber: nil, txnDetailsIds: [], scannedAt: 2)
        ]
        let json = try #require(bottles.encodedJson())
        let decoded = [BottleInfo].decode(from: json)
        #expect(decoded == bottles)
    }

    @Test func decodeNilReturnsEmptyArray() {
        #expect([BottleInfo].decode(from: nil) == [])
    }

    @Test func decodeGarbageReturnsEmptyArray() {
        #expect([BottleInfo].decode(from: "not valid json") == [])
    }

    @Test func decodeEmptyStringReturnsEmptyArray() {
        #expect([BottleInfo].decode(from: "") == [])
    }

    @Test func emptyArrayRoundTrips() throws {
        let bottles: [BottleInfo] = []
        let json = try #require(bottles.encodedJson())
        #expect([BottleInfo].decode(from: json) == [])
    }

    @Test func defaultTxnDetailsIdsIsEmpty() {
        let bottle = BottleInfo(lotNumber: nil, expirationDate: nil, serialNumber: nil, scannedAt: 5)
        #expect(bottle.txnDetailsIds == [])
    }
}
