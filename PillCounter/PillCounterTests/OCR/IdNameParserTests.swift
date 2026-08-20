//
//  IdNameParserTests.swift
//  PillCounterTests
//
//  22 cases ported from IdNameParserTest.kt (Android reference) — see
//  plans/face-auth/ocr/ID_SCAN_OCR_IMPLEMENTATION.md §5.7. These encode the
//  failure modes found during Android development; do not thin them out.
//

import Testing
@testable import PillCounter

struct IdNameParserTests {

    // MARK: - 1-2: prominence tier

    @Test func badgePicksProminentNameLineSkipsOrgAndRole() {
        let lines = [
            IdTextLine("Medical Center", 30),
            IdTextLine("Cole Paulson", 42),
            IdTextLine("ID# 123456", 18),
            IdTextLine("PHARMACIST", 36),
        ]
        #expect(IdNameParser.parse(lines) == IdCardName(firstName: "Cole", lastName: "Paulson"))
    }

    @Test func twoTwoWordLinesTallerWins() {
        let lines = [
            IdTextLine("Amy Reyes", 20),
            IdTextLine("Cole Paulson", 42),
        ]
        #expect(IdNameParser.parse(lines) == IdCardName(firstName: "Cole", lastName: "Paulson"))
    }

    // MARK: - 3-5: labeled tier

    @Test func licenseFrontLabeledLNFNFields() {
        let lines = [
            IdTextLine("CALIFORNIA DRIVER LICENSE", 20),
            IdTextLine("LN PAULSON", 24),
            IdTextLine("FN COLE ALAN", 24),
            IdTextLine("DOB 01/02/1990", 16),
        ]
        #expect(IdNameParser.parse(lines) == IdCardName(firstName: "Cole", lastName: "Paulson"))
    }

    @Test func licenseFrontNumberedFieldsWithAddressNoise() {
        let lines = [
            IdTextLine("1 PAULSON", 24),
            IdTextLine("2 COLE", 24),
            IdTextLine("8 100 MAIN ST", 16),
        ]
        #expect(IdNameParser.parse(lines) == IdCardName(firstName: "Cole", lastName: "Paulson"))
    }

    @Test func onlyNumberedAddressLineMustNotProduceAName() {
        let lines = [
            IdTextLine("1 MAIN ST", 16),
        ]
        #expect(IdNameParser.parse(lines) == nil)
    }

    // MARK: - 6-9: name-labeled tier

    @Test func nameLabelInline() {
        let lines = [
            IdTextLine("Name: Cole Paulson", 24),
        ]
        #expect(IdNameParser.parse(lines) == IdCardName(firstName: "Cole", lastName: "Paulson"))
    }

    @Test func bareNameLabelValueOnNextLine() {
        let lines = [
            IdTextLine("Name", 24),
            IdTextLine("Cole Paulson", 24),
        ]
        #expect(IdNameParser.parse(lines) == IdCardName(firstName: "Cole", lastName: "Paulson"))
    }

    @Test func stackedFirstNameLastNameLabels() {
        let lines = [
            IdTextLine("First Name", 20),
            IdTextLine("Cole", 24),
            IdTextLine("Last Name", 20),
            IdTextLine("Paulson", 24),
        ]
        #expect(IdNameParser.parse(lines) == IdCardName(firstName: "Cole", lastName: "Paulson"))
    }

    @Test func namesakeAwardsMustNotMatchNameLabel() {
        // "Namesake" must not trip the `\bNAME\b` label match (tier 2) — it
        // falls through to the prominence tier (tier 4) instead, which is
        // free to treat the two words as a name-shaped line.
        let lines = [
            IdTextLine("Namesake Awards", 24),
        ]
        #expect(IdNameParser.parse(lines) == IdCardName(firstName: "Namesake", lastName: "Awards"))
    }

    // MARK: - 10: falls through to prominence

    @Test func noLabelFallsThroughToProminence() {
        let lines = [
            IdTextLine("Acme Pharmacy", 20),
            IdTextLine("Cole Paulson", 34),
        ]
        #expect(IdNameParser.parse(lines) == IdCardName(firstName: "Cole", lastName: "Paulson"))
    }

    // MARK: - 11: comma tier

    @Test func commaNamePaulsonCole() {
        let lines = [
            IdTextLine("PAULSON, COLE", 24),
        ]
        #expect(IdNameParser.parse(lines) == IdCardName(firstName: "Cole", lastName: "Paulson"))
    }

    // MARK: - 12-13: stripped tokens, middle initial

    @Test func titlesAndCredentialsStripped() {
        let lines = [
            IdTextLine("DR COLE PAULSON RPH", 30),
        ]
        #expect(IdNameParser.parse(lines) == IdCardName(firstName: "Cole", lastName: "Paulson"))
    }

    @Test func middleInitialTolerated() {
        let lines = [
            IdTextLine("COLE A PAULSON", 30),
        ]
        #expect(IdNameParser.parse(lines) == IdCardName(firstName: "Cole", lastName: "Paulson"))
    }

    // MARK: - 14: displayCase punctuation

    @Test func displayCasePreservesApostropheAndHyphen() {
        #expect(IdNameParser.displayCase("O'BRIEN") == "O'Brien")
        #expect(IdNameParser.displayCase("SMITH-JONES") == "Smith-Jones")
    }

    // MARK: - 15-16: null cases

    @Test func emptyLineListReturnsNil() {
        #expect(IdNameParser.parse([]) == nil)
    }

    @Test func onlyExcludedVocabularyReturnsNil() {
        let lines = [
            IdTextLine("MEDICAL CENTER", 30),
            IdTextLine("PHARMACIST", 24),
        ]
        #expect(IdNameParser.parse(lines) == nil)
    }

    // MARK: - 17-22: candidateWords

    @Test func candidateWordsLabelAdjacentRankedFirst() {
        let lines = [
            IdTextLine("Medical Center", 40),
            IdTextLine("Name: Cole Paulson", 20),
        ]
        let words = IdNameParser.candidateWords(lines)
        #expect(words.first == "Cole")
        #expect(words.contains("Paulson"))
    }

    @Test func candidateWordsOrderedByHeight() {
        let lines = [
            IdTextLine("Amy Reyes", 20),
            IdTextLine("Cole Paulson", 42),
        ]
        let words = IdNameParser.candidateWords(lines)
        #expect(words == ["Cole", "Paulson", "Amy", "Reyes"])
    }

    @Test func candidateWordsDeduped() {
        let lines = [
            IdTextLine("Cole Paulson", 42),
            IdTextLine("Cole Paulson", 30),
        ]
        let words = IdNameParser.candidateWords(lines)
        #expect(words == ["Cole", "Paulson"])
    }

    @Test func candidateWordsCappedAtEight() {
        let lines = [
            IdTextLine("Aaa Bbb", 90),
            IdTextLine("Ccc Ddd", 80),
            IdTextLine("Eee Fff", 70),
            IdTextLine("Ggg Hhh", 60),
            IdTextLine("Iii Jjj", 50),
        ]
        let words = IdNameParser.candidateWords(lines)
        #expect(words.count == 8)
    }

    @Test func candidateWordsExcludesDigitLines() {
        let lines = [
            IdTextLine("ID# 123456", 40),
            IdTextLine("Cole Paulson", 30),
        ]
        let words = IdNameParser.candidateWords(lines)
        #expect(!words.contains("123456"))
        #expect(words == ["Cole", "Paulson"])
    }

    @Test func candidateWordsExcludesLinesOverFourWords() {
        let lines = [
            IdTextLine("This line has way too many words", 50),
            IdTextLine("Cole Paulson", 30),
        ]
        let words = IdNameParser.candidateWords(lines)
        #expect(words == ["Cole", "Paulson"])
    }
}
