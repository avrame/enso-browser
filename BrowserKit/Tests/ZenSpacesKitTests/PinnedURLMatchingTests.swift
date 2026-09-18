// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest
@testable import ZenSpacesKit

final class PinnedURLMatchingTests: XCTestCase {
    func testMatchesCosmeticDifferences() {
        XCTAssertTrue(same("https://example.com/", "https://example.com"))
        XCTAssertTrue(same("https://Example.com/inbox", "https://example.com/inbox/"))
        XCTAssertTrue(same("https://www.example.com/a", "https://example.com/a"))
        XCTAssertTrue(same("https://example.com/a#top", "https://example.com/a"))
    }

    func testDistinguishesDifferentPages() {
        XCTAssertFalse(same("https://example.com/a", "https://example.com/b"))
        XCTAssertFalse(same("https://example.com/?q=1", "https://example.com/?q=2"))
        XCTAssertFalse(same("http://example.com/", "https://example.com/"))
        XCTAssertFalse(same("https://mail.example.com/", "https://example.com/"))
        XCTAssertFalse(same("https://example.com:8443/", "https://example.com/"))
    }

    private func same(_ lhs: String, _ rhs: String) -> Bool {
        guard let lhs = URL(string: lhs), let rhs = URL(string: rhs) else { return false }
        return PinnedURLMatching.isSamePage(lhs, rhs)
    }
}
