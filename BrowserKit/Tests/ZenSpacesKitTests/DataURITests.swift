// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest
@testable import ZenSpacesKit

final class DataURITests: XCTestCase {
    private let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"/>"#

    func testBase64SVG() throws {
        let uri = try XCTUnwrap(DataURI("data:image/svg+xml;base64," + Data(svg.utf8).base64EncodedString()))
        XCTAssertTrue(uri.isSVG)
        XCTAssertEqual(String(decoding: uri.data, as: UTF8.self), svg)
    }

    func testPercentEncodedSVG() throws {
        let encoded = try XCTUnwrap(svg.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        let uri = try XCTUnwrap(DataURI("data:image/svg+xml," + encoded))
        XCTAssertTrue(uri.isSVG)
        XCTAssertEqual(String(decoding: uri.data, as: UTF8.self), svg)
    }

    func testUTF8ParameterAndUppercaseScheme() throws {
        let uri = try XCTUnwrap(DataURI("DATA:image/svg+xml;utf8," + svg))
        XCTAssertTrue(uri.isSVG)
        XCTAssertEqual(String(decoding: uri.data, as: UTF8.self), svg)
    }

    func testBinaryImageKeepsMediaType() throws {
        let uri = try XCTUnwrap(DataURI("data:image/png;base64,iVBORw0KGgo="))
        XCTAssertEqual(uri.mediaType, "image/png")
        XCTAssertFalse(uri.isSVG)
        XCTAssertEqual(uri.data.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
    }

    func testRejectsNonDataAndEmptyPayloads() {
        XCTAssertNil(DataURI("chrome://global/skin/icons/info.svg"))
        XCTAssertNil(DataURI("data:image/png;base64,"))
        XCTAssertNil(DataURI("data:image/png;base64"))
    }
}
