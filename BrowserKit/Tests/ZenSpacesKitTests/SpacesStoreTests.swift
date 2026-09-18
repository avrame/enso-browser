// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest
@testable import ZenSpacesKit

@MainActor
final class SpacesStoreTests: XCTestCase {
    private var cacheURL: URL!

    override func setUp() async throws {
        cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("spaces.json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent())
    }

    func testCacheRoundTripsRawRecords() throws {
        let cache = SpacesCache(url: cacheURL)
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try cache.save(records(spaceName: "Alpha"), fetchedAt: fetchedAt)

        let loaded = try XCTUnwrap(cache.load())
        XCTAssertEqual(loaded.fetchedAt, fetchedAt)
        XCTAssertEqual(SpacesSnapshot(records: loaded.records).spaces.map(\.record.name), ["Alpha"])
    }

    func testStoreStartsFromCacheThenRefreshes() async throws {
        let cache = SpacesCache(url: cacheURL)
        try cache.save(records(spaceName: "Cached"), fetchedAt: .distantPast)

        let fresh = records(spaceName: "Fresh")
        let store = SpacesStore(cache: cache) {
            SpacesFetchResult(records: fresh, snapshot: SpacesSnapshot(records: fresh), engineVersion: 3, fetchedAt: Date())
        }
        XCTAssertEqual(store.snapshot?.spaces.map(\.record.name), ["Cached"])

        await store.refresh()
        XCTAssertEqual(store.snapshot?.spaces.map(\.record.name), ["Fresh"])
        XCTAssertEqual(store.status, .idle)
        XCTAssertEqual(cache.load().map { SpacesSnapshot(records: $0.records).spaces.map(\.record.name) }, ["Fresh"])
    }

    func testFailedRefreshKeepsPreviousSnapshot() async throws {
        let cache = SpacesCache(url: cacheURL)
        try cache.save(records(spaceName: "Cached"), fetchedAt: .distantPast)
        let store = SpacesStore(cache: cache) { throw ZenSpacesError.engineNotOnServer }

        await store.refresh()
        XCTAssertEqual(store.snapshot?.spaces.map(\.record.name), ["Cached"])
        guard case .failed = store.status else { return XCTFail("\(store.status)") }
    }

    func testResetClearsCache() throws {
        let cache = SpacesCache(url: cacheURL)
        try cache.save(records(spaceName: "Cached"), fetchedAt: .distantPast)
        let store = SpacesStore(cache: cache) { throw ZenSpacesError.engineNotOnServer }

        store.reset()
        XCTAssertNil(store.snapshot)
        XCTAssertNil(cache.load())
    }

    private func records(spaceName: String) -> [SpacesRecord] {
        let space = #"{"id":"{a}","kind":"space","data":{"uuid":"{a}","name":"\#(spaceName)","children":[]}}"#
        let layout = #"{"id":"layout","kind":"layout","data":{"spaces":["{a}"],"essentials":{}}}"#
        return [
            SpacesRecord(id: "{a}", modified: .distantPast, cleartext: Data(space.utf8)),
            SpacesRecord(id: "layout", modified: .distantPast, cleartext: Data(layout.utf8)),
        ]
    }
}
