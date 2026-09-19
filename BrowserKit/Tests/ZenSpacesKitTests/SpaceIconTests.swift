// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest
@testable import ZenSpacesKit

final class SpaceIconTests: XCTestCase {
    func testReadsWhatZenStores() {
        // Values taken from a real account.
        XCTAssertEqual(SpaceIcon(stored: "💻️"), .emoji("💻️"))
        XCTAssertEqual(SpaceIcon(stored: "🧑‍🦰"), .emoji("🧑‍🦰"))
        XCTAssertEqual(SpaceIcon(stored: "chrome://browser/skin/zen-icons/selectable/circle.svg"), .zen("circle"))
        XCTAssertEqual(SpaceIcon(stored: nil), SpaceIcon.none)
        XCTAssertEqual(SpaceIcon(stored: ""), SpaceIcon.none)
        XCTAssertEqual(SpaceIcon(stored: "chrome://browser/skin/zen-icons/selectable/unknown.svg"), SpaceIcon.none)
        XCTAssertEqual(SpaceIcon(stored: "data:image/svg+xml;base64,AAAA"), SpaceIcon.none)
    }

    func testStoredRoundTrips() {
        for icon in [SpaceIcon.emoji("🏠"), .zen("globe-1"), .none] {
            XCTAssertEqual(SpaceIcon(stored: icon.stored), icon)
        }
    }

    func testEmojiCheck() {
        for emoji in ["🏠", "💻️", "🧑‍🦰", "👍🏽", "🇺🇸", "❤️"] {
            XCTAssertTrue(SpaceIcon.isEmoji(emoji), emoji)
        }
        for text in ["", "A", "ab", "1", "😀😀", "#"] {
            XCTAssertFalse(SpaceIcon.isEmoji(text), text)
        }
    }
}
