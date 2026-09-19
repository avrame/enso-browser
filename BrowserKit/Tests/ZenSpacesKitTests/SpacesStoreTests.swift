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
        let store = SpacesStore(cache: cache,
                                fetch: { result },
                                rename: Self.noRename,
                                pin: Self.noPin,
                                unpin: Self.noUnpin,
                                move: Self.noMove,
                                moveTab: Self.noMoveTab,
                                setIcon: Self.noSetIcon,
                                createSpace: Self.noCreateSpace)
        XCTAssertEqual(store.snapshot?.spaces.map(\.record.name), ["Cached"])

        await store.refresh()
        XCTAssertEqual(store.snapshot?.spaces.map(\.record.name), ["Fresh"])
        XCTAssertEqual(store.status, .idle)
        XCTAssertEqual(cache.load().map { SpacesSnapshot(records: $0.records).spaces.map(\.record.name) }, ["Fresh"])
    }

    func testFailedRefreshKeepsPreviousSnapshot() async throws {
        let cache = SpacesCache(url: cacheURL)
        try cache.save(records(spaceName: "Cached"), fetchedAt: .distantPast)
        let store = SpacesStore(cache: cache,
                                fetch: { throw ZenSpacesError.engineNotOnServer },
                                rename: Self.noRename,
                                pin: Self.noPin,
                                unpin: Self.noUnpin,
                                move: Self.noMove,
                                moveTab: Self.noMoveTab,
                                setIcon: Self.noSetIcon,
                                createSpace: Self.noCreateSpace)

        await store.refresh()
        XCTAssertEqual(store.snapshot?.spaces.map(\.record.name), ["Cached"])
        guard case .failed = store.status else { return XCTFail("\(store.status)") }
    }

    func testResetClearsCache() throws {
        let cache = SpacesCache(url: cacheURL)
        try cache.save(records(spaceName: "Cached"), fetchedAt: .distantPast)
        let store = SpacesStore(cache: cache,
                                fetch: { throw ZenSpacesError.engineNotOnServer },
                                rename: Self.noRename,
                                pin: Self.noPin,
                                unpin: Self.noUnpin,
                                move: Self.noMove,
                                moveTab: Self.noMoveTab,
                                setIcon: Self.noSetIcon,
                                createSpace: Self.noCreateSpace)

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
                                rename: { target, name in
                                    XCTAssertEqual(target, .space("{a}"))
                                    XCTAssertEqual(name, "New")
                                    return renamed
                                },
                                pin: Self.noPin,
                                unpin: Self.noUnpin,
                                move: Self.noMove,
                                moveTab: Self.noMoveTab,
                                setIcon: Self.noSetIcon,
                                createSpace: Self.noCreateSpace)

        try await store.rename(.space("{a}"), to: "New")
        XCTAssertEqual(store.snapshot?.spaces.map(\.record.name), ["New"])
        XCTAssertEqual(cache.load().map { SpacesSnapshot(records: $0.records).spaces.map(\.record.name) }, ["New"])
    }

    func testFailedRenameChangesNothing() async throws {
        let cache = SpacesCache(url: cacheURL)
        try cache.save(records(spaceName: "Old"), fetchedAt: .distantPast)
        let store = SpacesStore(cache: cache,
                                fetch: { throw ZenSpacesError.engineNotOnServer },
                                rename: { _, _ in throw ZenSpacesWriteError.conflict("{a}") },
                                pin: Self.noPin,
                                unpin: Self.noUnpin,
                                move: Self.noMove,
                                moveTab: Self.noMoveTab,
                                setIcon: Self.noSetIcon,
                                createSpace: Self.noCreateSpace)

        do {
            try await store.rename(.space("{a}"), to: "New")
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

        let kept = SpacesStore.merge(local: local, fetched: staleFetch, writtenLocally: ["{a}"])
        XCTAssertEqual(SpacesSnapshot(records: kept.records).spaces.map(\.record.name), ["Renamed"])
        XCTAssertEqual(kept.writtenLocally, ["{a}"])
        let replaced = SpacesStore.merge(local: local, fetched: newerFetch, writtenLocally: ["{a}"])
        XCTAssertEqual(SpacesSnapshot(records: replaced.records).spaces.map(\.record.name), ["Zen"])
        XCTAssertEqual(replaced.writtenLocally, [], "caught up")
        let notMine = SpacesStore.merge(local: local, fetched: staleFetch, writtenLocally: [])
        let names = SpacesSnapshot(records: notMine.records).spaces.map(\.record.name)
        XCTAssertEqual(names, ["Old"], "only records this store wrote are protected")
    }

    func testRefreshKeepsAJustCreatedRecordUntilTheServerHasIt() {
        let created = SpacesRecord(id: "t9",
                                   modified: Date(timeIntervalSince1970: 20),
                                   cleartext: Data(#"{"id":"t9","kind":"tab","data":{"tabId":"t9","url":"https://a/"}}"#.utf8))
        let local = records(spaceName: "Space") + [created]
        let fetchedWithout = records(spaceName: "Space")
        let merged = SpacesStore.merge(local: local, fetched: fetchedWithout, writtenLocally: ["t9"])
        XCTAssertTrue(merged.records.contains { $0.id == "t9" })

        let deletedElsewhere = SpacesStore.merge(local: local, fetched: fetchedWithout, writtenLocally: [])
        XCTAssertFalse(deletedElsewhere.records.contains { $0.id == "t9" }, "not ours: the server's view wins")
    }

    func testPinAddsTheTabAndUpdatedSpace() async throws {
        let cache = SpacesCache(url: cacheURL)
        try cache.save(records(spaceName: "Space"), fetchedAt: .distantPast)
        let tabJSON = #"{"id":"t9","kind":"tab","data":{"tabId":"t9","url":"https://a/","#
            + #""title":"A","pinned":true,"workspaceUuid":"{a}"}}"#
        let spaceJSON = #"{"id":"{a}","kind":"space","data":{"uuid":"{a}","name":"Space","children":["t9"]}}"#
        let tab = SpacesRecord(id: "t9", modified: Date(timeIntervalSince1970: 20), cleartext: Data(tabJSON.utf8))
        let space = SpacesRecord(id: "{a}", modified: Date(timeIntervalSince1970: 20), cleartext: Data(spaceJSON.utf8))
        let store = SpacesStore(cache: cache,
                                fetch: { throw ZenSpacesError.engineNotOnServer },
                                rename: Self.noRename,
                                pin: { _, _ in PinnedTab(tab: tab, space: space) },
                                unpin: Self.noUnpin,
                                move: Self.noMove,
                                moveTab: Self.noMoveTab,
                                setIcon: Self.noSetIcon,
                                createSpace: Self.noCreateSpace)

        let page = PinnablePage(url: try XCTUnwrap(URL(string: "https://a/")), title: "A")
        let pinned = try await store.pin(page, toSpace: "{a}")
        XCTAssertEqual(pinned?.tabId, "t9")
        guard case .tab(let item)? = store.snapshot?.spaces.first?.items.first else {
            return XCTFail("the pinned tab should be listed in the space")
        }
        XCTAssertEqual(item.url, "https://a/")
    }

    func testUnpinRemovesTheTabOnceTheServerAccepts() async throws {
        let cache = SpacesCache(url: cacheURL)
        let tabJSON = #"{"id":"t9","kind":"tab","data":{"tabId":"t9","url":"https://a/","pinned":true,"#
            + #""workspaceUuid":"{a}"}}"#
        let spaceJSON = #"{"id":"{a}","kind":"space","data":{"uuid":"{a}","name":"Space","children":["t9"]}}"#
        let layout = #"{"id":"layout","kind":"layout","data":{"spaces":["{a}"],"essentials":{}}}"#
        try cache.save([
            SpacesRecord(id: "t9", modified: .distantPast, cleartext: Data(tabJSON.utf8)),
            SpacesRecord(id: "{a}", modified: .distantPast, cleartext: Data(spaceJSON.utf8)),
            SpacesRecord(id: "layout", modified: .distantPast, cleartext: Data(layout.utf8)),
        ], fetchedAt: .distantPast)
        let emptied = #"{"id":"{a}","kind":"space","data":{"uuid":"{a}","name":"Space","children":[]}}"#
        let parent = SpacesRecord(id: "{a}", modified: Date(timeIntervalSince1970: 20), cleartext: Data(emptied.utf8))
        let tombstone = SpacesRecord(id: "t9",
                                     modified: Date(timeIntervalSince1970: 20),
                                     cleartext: Data(#"{"id":"t9","deleted":true}"#.utf8))
        let store = SpacesStore(cache: cache,
                                fetch: { throw ZenSpacesError.engineNotOnServer },
                                rename: Self.noRename,
                                pin: Self.noPin,
                                unpin: { _ in UnpinnedTab(parent: parent, tombstone: tombstone) },
                                move: Self.noMove,
                                moveTab: Self.noMoveTab,
                                setIcon: Self.noSetIcon,
                                createSpace: Self.noCreateSpace)
        XCTAssertEqual(store.snapshot?.spaces.first?.items.count, 1)

        try await store.unpin(tabID: "t9")
        XCTAssertEqual(store.snapshot?.spaces.first?.items, [])
        XCTAssertEqual(store.snapshot?.issues, [], "no dangling or unplaced records")
    }

    private func orderedCache() throws -> SpacesCache {
        let cache = SpacesCache(url: cacheURL)
        let space = #"{"id":"{a}","kind":"space","data":{"uuid":"{a}","name":"Space","children":["t1","t2","t3"]}}"#
        let layout = #"{"id":"layout","kind":"layout","data":{"spaces":["{a}"],"essentials":{}}}"#
        var records = [SpacesRecord(id: "{a}", modified: .distantPast, cleartext: Data(space.utf8)),
                       SpacesRecord(id: "layout", modified: .distantPast, cleartext: Data(layout.utf8))]
        for id in ["t1", "t2", "t3"] {
            let tab = #"{"id":"\#(id)","kind":"tab","data":{"tabId":"\#(id)","url":"https://\#(id)/","#
                + #""pinned":true,"workspaceUuid":"{a}"}}"#
            records.append(SpacesRecord(id: id, modified: .distantPast, cleartext: Data(tab.utf8)))
        }
        try cache.save(records, fetchedAt: .distantPast)
        return cache
    }

    private func order(_ store: SpacesStore) -> [String] {
        (store.snapshot?.spaces.first?.items ?? []).compactMap { item in
            if case .tab(let tab) = item { return tab.tabId }
            return nil
        }
    }

    func testMoveShowsAtOnceAndKeepsTheServersResult() async throws {
        let cache = try orderedCache()
        var seenDuringWrite: [String] = []
        var store: SpacesStore?
        let server = #"{"id":"{a}","kind":"space","data":{"uuid":"{a}","name":"Space","children":["t3","t1","t2"]}}"#
        store = SpacesStore(cache: cache,
                            fetch: { throw ZenSpacesError.engineNotOnServer },
                            rename: Self.noRename,
                            pin: Self.noPin,
                            unpin: Self.noUnpin,
                            move: { itemID, parent, before in
                                XCTAssertEqual(itemID, "t3")
                                XCTAssertEqual(parent, .space("{a}"))
                                XCTAssertEqual(before, "t1")
                                seenDuringWrite = store.map(self.order) ?? []
                                return SpacesRecord(id: "{a}", modified: Date(), cleartext: Data(server.utf8))
                            },
                            moveTab: Self.noMoveTab,
                            setIcon: Self.noSetIcon,
                            createSpace: Self.noCreateSpace)
        let subject = try XCTUnwrap(store)

        try await subject.move("t3", in: .space("{a}"), before: "t1")
        XCTAssertEqual(seenDuringWrite, ["t3", "t1", "t2"], "shown before the server answered")
        XCTAssertEqual(order(subject), ["t3", "t1", "t2"])
    }

    func testFailedMoveRollsBack() async throws {
        let store = SpacesStore(cache: try orderedCache(),
                                fetch: { throw ZenSpacesError.engineNotOnServer },
                                rename: Self.noRename,
                                pin: Self.noPin,
                                unpin: Self.noUnpin,
                                move: { _, _, _ in throw ZenSpacesWriteError.conflict("{a}") },
                                moveTab: Self.noMoveTab,
                                setIcon: Self.noSetIcon,
                                createSpace: Self.noCreateSpace)
        do {
            try await store.move("t3", in: .space("{a}"), before: "t1")
            XCTFail("expected the error to surface")
        } catch {
            XCTAssertEqual(error as? ZenSpacesWriteError, .conflict("{a}"))
        }
        XCTAssertEqual(order(store), ["t1", "t2", "t3"])
    }

    func testMovesAreSentInOrder() async throws {
        var sent: [String] = []
        let store = SpacesStore(cache: try orderedCache(),
                                fetch: { throw ZenSpacesError.engineNotOnServer },
                                rename: Self.noRename,
                                pin: Self.noPin,
                                unpin: Self.noUnpin,
                                move: { itemID, _, _ in
                                    sent.append("start \(itemID)")
                                    try await Task.sleep(for: .milliseconds(itemID == "t3" ? 50 : 1))
                                    sent.append("end \(itemID)")
                                    throw ZenSpacesWriteError.conflict(itemID)
                                },
                                moveTab: Self.noMoveTab,
                                setIcon: Self.noSetIcon,
                                createSpace: Self.noCreateSpace)
        async let first: Void? = try? store.move("t3", in: .space("{a}"), before: "t1")
        async let second: Void? = try? store.move("t2", in: .space("{a}"), before: nil)
        _ = await (first, second)
        XCTAssertEqual(sent, ["start t3", "end t3", "start t2", "end t2"])
    }

    private static let noRename: SpacesStore.Rename = { _, _ in throw ZenSpacesWriteError.invalidName }
    private static let noPin: SpacesStore.Pin = { _, _ in throw ZenSpacesWriteError.invalidName }
    private static let noUnpin: SpacesStore.Unpin = { _ in throw ZenSpacesWriteError.invalidName }
    private static let noMove: SpacesStore.Move = { _, _, _ in throw ZenSpacesWriteError.invalidName }
    private static let noMoveTab: SpacesStore.MoveTab = { _, _ in throw ZenSpacesWriteError.invalidName }
    private static let noSetIcon: SpacesStore.SetIcon = { _, _ in throw ZenSpacesWriteError.invalidName }
    private static let noCreateSpace: SpacesStore.CreateSpace = { _ in throw ZenSpacesWriteError.invalidName }

    private func records(spaceName: String, modified: Date = .distantPast) -> [SpacesRecord] {
        let space = #"{"id":"{a}","kind":"space","data":{"uuid":"{a}","name":"\#(spaceName)","children":[]}}"#
        let layout = #"{"id":"layout","kind":"layout","data":{"spaces":["{a}"],"essentials":{}}}"#
        return [
            SpacesRecord(id: "{a}", modified: modified, cleartext: Data(space.utf8)),
            SpacesRecord(id: "layout", modified: modified, cleartext: Data(layout.utf8)),
        ]
    }
}
