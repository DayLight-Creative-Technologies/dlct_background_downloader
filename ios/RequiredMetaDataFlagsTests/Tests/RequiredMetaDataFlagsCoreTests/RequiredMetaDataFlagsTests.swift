//
//  RequiredMetaDataFlagsTests.swift
//  RequiredMetaDataFlagsTests
//
//  [DLCT] Tests for the required-metaData-flag veto parser and decision,
//  compiled from the plugin's own RequiredMetaDataFlags.swift. Same case matrix
//  as the Kotlin RequiredMetaDataFlagsTest (android/src/test/kotlin).
//

import XCTest
@testable import RequiredMetaDataFlagsCore

final class RequiredMetaDataFlagsTests: XCTestCase {

    private let declared = RequiredMetaDataFlags.parse("mediaUploads=scrubbed")
    private let twoGroups = RequiredMetaDataFlags.parse("mediaUploads=scrubbed,avatars=resized")

    private func isMalformed(_ flags: RequiredMetaDataFlags) -> Bool {
        if case .malformed = flags {
            return true
        }
        return false
    }

    private func isVetoed(_ group: String, _ metaData: String, _ flags: RequiredMetaDataFlags) -> Bool {
        return RequiredMetaDataFlags.isVetoed(group: group, metaData: metaData, flags: flags)
    }

    // MARK: parse

    func testNilOrBlankDeclarationIsNone() {
        XCTAssertEqual(RequiredMetaDataFlags.parse(nil), RequiredMetaDataFlags.none)
        XCTAssertEqual(RequiredMetaDataFlags.parse(""), RequiredMetaDataFlags.none)
        XCTAssertEqual(RequiredMetaDataFlags.parse("   "), RequiredMetaDataFlags.none)
    }

    func testSinglePairIsParsed() {
        XCTAssertEqual(declared, RequiredMetaDataFlags.declared(["mediaUploads": "scrubbed"]))
    }

    func testMultiplePairsWithWhitespaceAndEmptySegmentsAreParsed() {
        XCTAssertEqual(
            RequiredMetaDataFlags.parse(" a = k1 , ,b=k2, "),
            RequiredMetaDataFlags.declared(["a": "k1", "b": "k2"])
        )
    }

    func testEntryWithoutEqualsSignIsMalformed() {
        XCTAssertTrue(isMalformed(RequiredMetaDataFlags.parse("mediaUploads")))
        XCTAssertTrue(isMalformed(RequiredMetaDataFlags.parse("a=k1,b")))
    }

    func testEntryWithMoreThanOneEqualsSignIsMalformed() {
        XCTAssertTrue(isMalformed(RequiredMetaDataFlags.parse("a=k=v")))
    }

    func testEntryWithEmptyGroupOrKeyIsMalformed() {
        XCTAssertTrue(isMalformed(RequiredMetaDataFlags.parse("=k")))
        XCTAssertTrue(isMalformed(RequiredMetaDataFlags.parse("a=")))
        XCTAssertTrue(isMalformed(RequiredMetaDataFlags.parse(" = ")))
    }

    func testGroupListedTwiceIsMalformed() {
        XCTAssertTrue(isMalformed(RequiredMetaDataFlags.parse("a=k1,a=k2")))
        XCTAssertTrue(isMalformed(RequiredMetaDataFlags.parse("a=k1,a=k1")))
    }

    func testDeclarationWithOnlySeparatorsIsMalformed() {
        XCTAssertTrue(isMalformed(RequiredMetaDataFlags.parse(",")))
        XCTAssertTrue(isMalformed(RequiredMetaDataFlags.parse(" , , ")))
    }

    // MARK: isVetoed

    func testNoDeclarationNeverVetoes() {
        XCTAssertFalse(isVetoed("mediaUploads", "", .none))
        XCTAssertFalse(isVetoed("mediaUploads", "not json", .none))
    }

    func testMalformedDeclarationVetoesEveryTask() {
        let malformed = RequiredMetaDataFlags.parse("mediaUploads")
        XCTAssertTrue(isVetoed("mediaUploads", #"{"scrubbed":true}"#, malformed))
        XCTAssertTrue(isVetoed("default", "", malformed))
    }

    func testUnlistedGroupIsNeverVetoed() {
        XCTAssertFalse(isVetoed("default", "", declared))
        XCTAssertFalse(isVetoed("default", #"{"scrubbed":false}"#, declared))
    }

    func testListedGroupWithBooleanTrueFlagRuns() {
        XCTAssertFalse(isVetoed("mediaUploads", #"{"scrubbed":true}"#, declared))
        XCTAssertFalse(isVetoed("mediaUploads", #"{"other":1,"scrubbed": true,"nested":{"x":[1,2]}}"#, declared))
    }

    func testListedGroupWithoutTheFlagIsVetoed() {
        XCTAssertTrue(isVetoed("mediaUploads", "", declared))
        XCTAssertTrue(isVetoed("mediaUploads", "{}", declared))
        XCTAssertTrue(isVetoed("mediaUploads", #"{"other":true}"#, declared))
    }

    func testListedGroupWithNonBooleanTrueFlagValueIsVetoed() {
        XCTAssertTrue(isVetoed("mediaUploads", #"{"scrubbed":false}"#, declared))
        XCTAssertTrue(isVetoed("mediaUploads", #"{"scrubbed":"true"}"#, declared))
        XCTAssertTrue(isVetoed("mediaUploads", #"{"scrubbed":1}"#, declared))
        XCTAssertTrue(isVetoed("mediaUploads", #"{"scrubbed":1.0}"#, declared))
        XCTAssertTrue(isVetoed("mediaUploads", #"{"scrubbed":null}"#, declared))
        XCTAssertTrue(isVetoed("mediaUploads", #"{"scrubbed":[true]}"#, declared))
        XCTAssertTrue(isVetoed("mediaUploads", #"{"scrubbed":{"v":true}}"#, declared))
    }

    func testListedGroupWithMetaDataThatIsNotAJsonObjectIsVetoed() {
        XCTAssertTrue(isVetoed("mediaUploads", "not json", declared))
        XCTAssertTrue(isVetoed("mediaUploads", "true", declared))
        XCTAssertTrue(isVetoed("mediaUploads", #"[{"scrubbed":true}]"#, declared))
        XCTAssertTrue(isVetoed("mediaUploads", #""scrubbed""#, declared))
        XCTAssertTrue(isVetoed("mediaUploads", #"{"scrubbed":true"#, declared))
    }

    func testFlagKeyMatchIsCaseSensitive() {
        XCTAssertTrue(isVetoed("mediaUploads", #"{"Scrubbed":true}"#, declared))
        XCTAssertFalse(isVetoed("MediaUploads", "", declared))
    }

    func testEveryDeclaredGroupRequiresItsOwnKey() {
        XCTAssertFalse(isVetoed("mediaUploads", #"{"scrubbed":true}"#, twoGroups))
        XCTAssertFalse(isVetoed("avatars", #"{"resized":true}"#, twoGroups))
        XCTAssertTrue(isVetoed("mediaUploads", "{}", twoGroups))
        XCTAssertTrue(isVetoed("avatars", "{}", twoGroups))
        XCTAssertTrue(isVetoed("avatars", #"{"resized":false}"#, twoGroups))
    }

    func testAnotherGroupsKeyDoesNotSatisfyTheFlag() {
        XCTAssertTrue(isVetoed("mediaUploads", #"{"resized":true}"#, twoGroups))
        XCTAssertTrue(isVetoed("avatars", #"{"scrubbed":true}"#, twoGroups))
        XCTAssertFalse(isVetoed("default", "", twoGroups))
    }
}
