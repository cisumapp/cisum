//
//  MatchedBindingResetTests.swift
//  ModelsTests
//
//  Which stored YouTube bindings the one-time matcher reset may forget.
//

@testable import Models
import XCTest

final class MatchedBindingResetTests: XCTestCase {
    private func isMatched(_ sourceID: String, _ siblings: [String]) -> Bool {
        ProviderBindingPolicy.isSearchMatchedYouTubeBinding(sourceID: sourceID, siblingSourceIDs: siblings)
    }

    func testYouTubeRowOnSpotifySongIsForgotten() {
        XCTAssertTrue(isMatched("youtube_music", ["spotify", "youtube_music"]))
        XCTAssertTrue(isMatched("youtube", ["saavn", "youtube"]))
    }

    func testYouTubeOnlySongIsKept() {
        XCTAssertFalse(isMatched("youtube_music", ["youtube_music"]))
        XCTAssertFalse(isMatched("youtube", ["youtube_music", "youtube"]))
    }

    func testNonYouTubeRowIsNeverForgotten() {
        XCTAssertFalse(isMatched("spotify", ["spotify", "youtube_music"]))
    }
}
