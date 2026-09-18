// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest
@testable import ZenSpacesKit

final class SpaceThemeTests: XCTestCase {
    func testParsesZenGradientWithPrimaryFirst() throws {
        // Shape taken from a real synced space.
        let theme = try XCTUnwrap(SpaceTheme(json(#"""
        {"type":"gradient","opacity":0.789,"texture":0.5,"gradientColors":[
          {"c":[74,65,241],"isPrimary":false,"isCustom":false,"lightness":"60"},
          {"c":[255,0,0],"isPrimary":true,"isCustom":false,"lightness":"60"}]}
        """#)))
        XCTAssertEqual(theme.primary, SpaceTheme.RGB(red: 1, green: 0, blue: 0))
        XCTAssertEqual(theme.colors.count, 2)
        XCTAssertEqual(theme.opacity, 0.789, accuracy: 0.0001)
        XCTAssertEqual(theme.texture, 0.5)
    }

    func testCustomCSSColors() {
        XCTAssertEqual(SpaceTheme.cssColor("#ff8000"), SpaceTheme.RGB(red: 1, green: 128.0 / 255, blue: 0))
        XCTAssertEqual(SpaceTheme.cssColor("#0f0"), SpaceTheme.RGB(red: 0, green: 1, blue: 0))
        XCTAssertEqual(SpaceTheme.cssColor("rgb(0, 0, 255)"), SpaceTheme.RGB(red: 0, green: 0, blue: 1))
        XCTAssertEqual(SpaceTheme.cssColor("rgba(255 255 255 / 0.5)"), SpaceTheme.RGB(red: 1, green: 1, blue: 1))
        XCTAssertNil(SpaceTheme.cssColor("var(--zen-primary)"))

        let theme = SpaceTheme(json(#"""
        {"type":"gradient","gradientColors":[{"c":"#000000","isCustom":true,"isPrimary":true}]}
        """#))
        XCTAssertEqual(theme?.primary, SpaceTheme.RGB(red: 0, green: 0, blue: 0))
        XCTAssertEqual(theme?.opacity, 0.5, "defaults when missing")
    }

    func testNoUsableGradientIsNil() {
        XCTAssertNil(SpaceTheme(json(#"{"type":"gradient","gradientColors":[],"opacity":0.5,"texture":0}"#)))
        XCTAssertNil(SpaceTheme(json(#"{"type":"image","gradientColors":[{"c":[1,2,3]}]}"#)))
        XCTAssertNil(SpaceTheme(json(#"{"type":"gradient","gradientColors":[{"c":[1,2]},{"c":null}]}"#)))
        XCTAssertNil(SpaceTheme(nil))
    }

    func testClampsOutOfRangeValues() throws {
        let theme = try XCTUnwrap(SpaceTheme(json(#"""
        {"type":"gradient","opacity":3,"texture":-1,"gradientColors":[{"c":[300,-5,128],"isPrimary":true}]}
        """#)))
        XCTAssertEqual(theme.opacity, 1)
        XCTAssertEqual(theme.texture, 0)
        XCTAssertEqual(theme.primary?.red, 1)
        XCTAssertEqual(theme.primary?.green, 0)
    }

    private func json(_ text: String) -> JSONValue? {
        try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }
}
