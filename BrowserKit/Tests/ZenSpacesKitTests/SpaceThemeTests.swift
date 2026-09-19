// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest
@testable import ZenSpacesKit

final class SpaceThemeTests: XCTestCase {
    func testKeepsZensOrderAndFindsThePrimary() throws {
        // Shape taken from a real synced space.
        let theme = try XCTUnwrap(SpaceTheme(json(#"""
        {"type":"gradient","opacity":0.789,"texture":0.5,"gradientColors":[
          {"c":[74,65,241],"isPrimary":false,"isCustom":false,"lightness":"60"},
          {"c":[255,0,0],"isPrimary":true,"isCustom":false,"lightness":"60"}]}
        """#)))
        XCTAssertEqual(theme.colors.map(\.rgb.red), [74.0 / 255, 1], "stored order, as Zen draws them")
        XCTAssertEqual(theme.primary, SpaceTheme.RGB(red: 1, green: 0, blue: 0))
        XCTAssertEqual(theme.opacity, 0.789, accuracy: 0.0001)
        XCTAssertEqual(theme.texture, 0.5)
    }

    func testWithoutAMarkedPrimaryZenUsesTheMiddleColor() throws {
        let theme = try XCTUnwrap(SpaceTheme(json(#"""
        {"type":"gradient","gradientColors":[{"c":[0,0,0]},{"c":[255,255,255]},{"c":[255,0,0]}]}
        """#)))
        XCTAssertEqual(theme.primary, SpaceTheme.RGB(red: 1, green: 1, blue: 1))
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
        XCTAssertEqual(theme?.colors.first?.isCustom, true)
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

final class ZenGradientTests: XCTestCase {
    private func rgb(_ red: Double, _ green: Double, _ blue: Double) -> SpaceTheme.RGB {
        SpaceTheme.RGB(red: red / 255, green: green / 255, blue: blue / 255)
    }

    private func theme(_ colors: [SpaceTheme.RGB], opacity: Double = 1, custom: Bool = false) -> SpaceTheme {
        SpaceTheme(colors: colors.map { SpaceTheme.Color(rgb: $0, isCustom: custom) }, opacity: opacity, texture: 0.25)
    }

    func testNoThemeMeansZensDefault() {
        XCTAssertNil(ZenGradient(theme: nil, dark: true))
    }

    func testColorsAreMixedWithZensBaseByOpacity() throws {
        // Capsas: one blue at 0.789 in a dark window.
        let gradient = try XCTUnwrap(ZenGradient(theme: theme([rgb(77, 116, 178)], opacity: 0.789), dark: true))
        guard case .linear(_, let stops) = gradient.layers.first, let color = stops.first?.color else {
            return XCTFail("\(gradient.layers)")
        }
        XCTAssertEqual(color.red * 255, 77 * 0.789 + 23 * 0.211, accuracy: 0.001)
        XCTAssertEqual(color.blue * 255, 178 * 0.789 + 26 * 0.211, accuracy: 0.001)
        XCTAssertEqual(gradient.grain, 0.25)
    }

    func testCustomColorsAreNotMixedAndGoEvenlySpaced() throws {
        let gradient = try XCTUnwrap(ZenGradient(theme: theme([rgb(255, 0, 0), rgb(0, 0, 255)], opacity: 0.2, custom: true),
                                                 dark: false))
        XCTAssertEqual(gradient.layers, [.linear(angle: -30, stops: [
            ZenGradient.Stop(color: rgb(255, 0, 0), location: 0),
            ZenGradient.Stop(color: rgb(0, 0, 255), location: 1),
        ])])
    }

    func testTwoColorsAreTwoOpposedFades() throws {
        let (first, second) = (rgb(255, 0, 0), rgb(0, 0, 255))
        let gradient = try XCTUnwrap(ZenGradient(theme: theme([first, second]), dark: true))
        XCTAssertEqual(gradient.layers, [
            .linear(angle: -30, stops: [ZenGradient.Stop(color: second, location: 0.3),
                                        ZenGradient.Stop(color: nil, location: 1.2)]),
            .linear(angle: 150, stops: [ZenGradient.Stop(color: first, location: 0.3),
                                        ZenGradient.Stop(color: nil, location: 1.2)]),
        ])
    }

    func testThreeColorsAreTwoCornerGlowsUnderABottomFade() throws {
        let colors = [rgb(65, 195, 241), rgb(74, 65, 241), rgb(64, 242, 145)]
        let gradient = try XCTUnwrap(ZenGradient(theme: theme(colors), dark: true))
        XCTAssertEqual(gradient.layers, [
            .radial(centerX: 0, centerY: 0, stops: [ZenGradient.Stop(color: colors[0], location: 0.1),
                                                    ZenGradient.Stop(color: nil, location: 0.7)]),
            .radial(centerX: 0.95, centerY: 0, stops: [ZenGradient.Stop(color: colors[1], location: 0),
                                                       ZenGradient.Stop(color: nil, location: 0.75)]),
            .linear(angle: -5, stops: [ZenGradient.Stop(color: colors[2], location: 0.1),
                                       ZenGradient.Stop(color: nil, location: 0.8)]),
        ])
    }

    func testTextSchemeFollowsZensContrastRule() throws {
        let navy = try XCTUnwrap(ZenGradient(theme: theme([rgb(20, 30, 90)]), dark: false))
        XCTAssertFalse(navy.prefersDarkText, "a dark color gets light text even in light mode")
        let lemon = try XCTUnwrap(ZenGradient(theme: theme([rgb(250, 240, 120)]), dark: true))
        XCTAssertTrue(lemon.prefersDarkText, "a light color gets dark text even in dark mode")
    }
}
