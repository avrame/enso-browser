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
        let result = SpacesFetchResult(records: fresh,
                                       snapshot: SpacesSnapshot(records: fresh),
                                       engineVersion: 3,
                                       fetchedAt: Date())
        let store = SpacesStore(cache: cache, fetch: { result }, rename: Self.noRename)
        XCTAssertEqual(store.snapshot?.spaces.map(\.record.name), ["Cached"])

        await store.refresh()
        XCTAssertEqual(store.snapshot?.spaces.map(\.record.name), ["Fresh"])
        XCTAssertEqual(store.status, .idle)
        XCTAssertEqual(cache.load().map { SpacesSnapshot(records: $0.records).spaces.map(\.record.name) }, ["Fresh"])
    }

    func testFailedRefreshKeepsPreviousSnapshot() async throws {
        let cache = SpacesCache(url: cacheURL)
        try cache.save(records(spaceName: "Cached"), fetchedAt: .distantPast)
        let store = SpacesStore(cache: cache, fetch: { throw ZenSpacesError.engineNotOnServer }, rename: Self.noRename)

        await store.refresh()
        XCTAssertEqual(store.snapshot?.spaces.map(\.record.name), ["Cached"])
        guard case .failed = store.status else { return XCTFail("\(store.status)") }
    }

    func testResetClearsCache() throws {
        let cache = SpacesCache(url: cacheURL)
        try cache.save(records(spaceName: "Cached"), fetchedAt: .distantPast)
        let store = SpacesStore(cache: cache, fetch: { throw ZenSpacesError.engineNotOnServer }, rename: Self.noRename)

        store.reset()
        XCTAssertNil(store.snapshot)
        XCTAssertNil(cache.load())
    }

    func testRenameUpdatesSnapshotAndCacheOnlyAfterTheServerAccepts() async throws {
        let cache = SpacesCache(url: cacheURL)
        try cache.save(records(spaceName: "Old"), fetchedAt: .distantPast)
        let renamed = records(spaceName: "New", modified: Date(timeIntervalSince1970: 1_700_000_010))[0]
        let store = SpacesStore(cache: cache,
                                fetch: { throw ZenSpacesError.engineNotOnServer },
                                rename: { uuid, name in
                                    XCTAssertEqual(uuid, "{a}")
                                    XCTAssertEqual(name, "New")
                                    return renamed
                                })

        try await store.renameSpace("{a}", to: "New")
        XCTAssertEqual(store.snapshot?.spaces.map(\.record.name), ["New"])
        XCTAssertEqual(cache.load().map { SpacesSnapshot(records: $0.records).spaces.map(\.record.name) }, ["New"])
    }

    func testFailedRenameChangesNothing() async throws {
        let cache = SpacesCache(url: cacheURL)
        try cache.save(records(spaceName: "Old"), fetchedAt: .distantPast)
        let store = SpacesStore(cache: cache,
                                fetch: { throw ZenSpacesError.engineNotOnServer },
                                rename: { _, _ in throw ZenSpacesWriteError.conflict("{a}") })

        do {
            try await store.renameSpace("{a}", to: "New")
            XCTFail("expected the error to surface")
        } catch {
            XCTAssertEqual(error as? ZenSpacesWriteError, .conflict("{a}"))
        }
        XCTAssertEqual(store.snapshot?.spaces.map(\.record.name), ["Old"])
    }

    func testRefreshDoesNotUndoANewerLocalWrite() {
        let local = records(spaceName: "Renamed", modified: Date(timeIntervalSince1970: 20))
        let staleFetch = records(spaceName: "Old", modified: Date(timeIntervalSince1970: 10))
        let newerFetch = records(spaceName: "Zen", modified: Date(timeIntervalSince1970: 30))

        let kept = SpacesStore.keepingNewer(local: local, fetched: staleFetch)
        XCTAssertEqual(SpacesSnapshot(records: kept).spaces.map(\.record.name), ["Renamed"])
        let replaced = SpacesStore.keepingNewer(local: local, fetched: newerFetch)
        XCTAssertEqual(SpacesSnapshot(records: replaced).spaces.map(\.record.name), ["Zen"])
    }

    private static let noRename: SpacesStore.Rename = { _, _ in throw ZenSpacesWriteError.invalidName }

    private func records(spaceName: String, modified: Date = .distantPast) -> [SpacesRecord] {
        let space = #"{"id":"{a}","kind":"space","data":{"uuid":"{a}","name":"\#(spaceName)","children":[]}}"#
        let layout = #"{"id":"layout","kind":"layout","data":{"spaces":["{a}"],"essentials":{}}}"#
        return [
            SpacesRecord(id: "{a}", modified: modified, cleartext: Data(space.utf8)),
            SpacesRecord(id: "layout", modified: modified, cleartext: Data(layout.utf8)),
        ]
    }
}
