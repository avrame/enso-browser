// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest
@testable import ZenSpacesKit

final class SVGColorSchemeTests: XCTestCase {
    // The shape Astro's docs favicon uses.
    private let astro = "<style> g { fill: #000; } @media (prefers-color-scheme: dark) { g { fill: #FFF; } } </style>"

    func testLightDropsDarkBlock() {
        XCTAssertEqual(SVGColorScheme.resolve(astro, dark: false), "<style> g { fill: #000; }  </style>")
    }

    func testDarkUnwrapsDarkBlock() {
        XCTAssertEqual(SVGColorScheme.resolve(astro, dark: true),
                       "<style> g { fill: #000; }  g { fill: #FFF; }  </style>")
    }

    func testLightBlockAndOtherQueries() {
        let svg = "a @media (prefers-color-scheme:light){x{fill:red}} b @media (min-width: 10px){y{fill:blue}} c"
        XCTAssertEqual(SVGColorScheme.resolve(svg, dark: false),
                       "a x{fill:red} b @media (min-width: 10px){y{fill:blue}} c")
        XCTAssertEqual(SVGColorScheme.resolve(svg, dark: true),
                       "a  b @media (min-width: 10px){y{fill:blue}} c")
    }

    func testLeavesUnrelatedAndMalformedInputAlone() {
        XCTAssertEqual(SVGColorScheme.resolve("<svg/>", dark: false), "<svg/>")
        let unclosed = "x @media (prefers-color-scheme: dark) { g { fill: #FFF; }"
        XCTAssertEqual(SVGColorScheme.resolve(unclosed, dark: false), unclosed)
    }
}
