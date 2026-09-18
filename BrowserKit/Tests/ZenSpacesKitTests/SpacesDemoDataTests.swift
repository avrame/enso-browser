// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest
@testable import ZenSpacesKit

final class SpacesDemoDataTests: XCTestCase {
    func testGeneratesAConsistentSnapshot() {
        let snapshot = SpacesSnapshot(records: SpacesDemoData.records(spaceCount: 30))

        XCTAssertEqual(snapshot.spaces.count, 30)
        XCTAssertEqual(snapshot.spaces.first?.record.name, "Space 1")
        XCTAssertEqual(snapshot.issues, [])
        guard case .folder(let folder)? = snapshot.spaces.first?.items.first else {
            return XCTFail("first item should be the folder")
        }
        XCTAssertEqual(folder.items.count, 1)
        XCTAssertEqual(snapshot.spaces.first?.items.count, 4)
    }
}
