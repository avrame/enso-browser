// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest
@testable import ZenSpacesKit

final class PinnedTabLinksTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "PinnedTabLinksTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testLinkSurvivesANewInstance() {
        PinnedTabLinks(defaults: defaults).link("pinned-1", to: "tab-A")

        let relaunched = PinnedTabLinks(defaults: defaults)
        XCTAssertEqual(relaunched.browserTab(for: "pinned-1") { _ in true }, "tab-A")
    }

    func testClosedTabIsForgotten() {
        let links = PinnedTabLinks(defaults: defaults)
        links.link("pinned-1", to: "tab-A")

        XCTAssertNil(links.browserTab(for: "pinned-1") { _ in false })
        XCTAssertNil(links.browserTab(for: "pinned-1") { _ in true }, "the stale link was removed")
    }

    func testBrowserTabBelongsToOnePinnedTab() {
        let links = PinnedTabLinks(defaults: defaults)
        links.link("pinned-1", to: "tab-A")
        links.link("pinned-2", to: "tab-A")

        XCTAssertNil(links.browserTab(for: "pinned-1") { _ in true })
        XCTAssertEqual(links.browserTab(for: "pinned-2") { _ in true }, "tab-A")
    }
}
