import Foundation
import Testing
@testable import Aesthetics

@Test func spotifyUpgradesToLargestAndKeepsHash() {
    let low = URL(string: "https://i.scdn.co/image/ab67616d00001e02abc123def456abc123def4560")!
    let best = ArtworkURL.best(from: low)!.absoluteString
    #expect(best.contains("ab67616d0000b273")) // 640² size code
    #expect(best.hasSuffix("abc123def456abc123def4560")) // unique hash untouched
}

@Test func iTunesUpgradesTo1000() {
    let low = URL(string: "https://is1-ssl.mzstatic.com/image/thumb/xyz/100x100bb.jpg")!
    #expect(ArtworkURL.best(from: low)!.absoluteString.contains("1000x1000bb.jpg"))
}

@Test func youTubeMusicUpgradesTo1000() {
    let low = URL(string: "https://lh3.googleusercontent.com/abc=w120-h120")!
    #expect(ArtworkURL.best(from: low)!.absoluteString.contains("w1000-h1000"))
}
