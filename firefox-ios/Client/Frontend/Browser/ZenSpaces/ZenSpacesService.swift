// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Account
import ZenSpacesKit

/// The app-wide spaces store, shared by every window.
@MainActor
enum ZenSpacesService {
    static let store = makeStore()
    static let pinnedTabLinks = PinnedTabLinks()

    private static let directory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ZenSpaces")

    private static func makeStore() -> SpacesStore {
        #if MOZ_CHANNEL_developer
        // Launch with ZEN_SPACES_DEMO=<count> to show generated spaces instead of the account's.
        if let count = ProcessInfo.processInfo.environment["ZEN_SPACES_DEMO"].flatMap(Int.init), count > 0 {
            let demo = DemoSpaces(records: SpacesDemoData.records(spaceCount: count))
            return SpacesStore(cache: SpacesCache(url: directory.appendingPathComponent("demo.json")),
                               fetch: demo.fetch,
                               rename: demo.rename,
                               pin: demo.pin)
        }
        #endif
        return SpacesStore(cache: SpacesCache(url: directory.appendingPathComponent("spaces.json")),
                           fetch: fetch,
                           rename: rename,
                           pin: pin)
    }

    private static func fetch() async throws -> SpacesFetchResult {
        try await ZenSpacesReader(auth: auth()).fetch()
    }

    private static func rename(_ target: RenameTarget, _ name: String) async throws -> SpacesRecord {
        try await ZenSpacesWriter(auth: auth()).rename(target, to: name)
    }

    private static func pin(_ url: URL, _ title: String, _ spaceUUID: String) async throws -> PinnedTab {
        try await ZenSpacesWriter(auth: auth()).pinTab(url: url, title: title, inSpace: spaceUUID)
    }

    private static func auth() async throws -> SyncAuth {
        try await ZenSpacesAuthProvider(accountManager: RustFirefoxAccounts.shared.accountManager).auth()
    }
}

/// In-memory stand-in for the server in demo mode.
@MainActor
private final class DemoSpaces {
    private var records: [SpacesRecord]

    init(records: [SpacesRecord]) {
        self.records = records
    }

    func fetch() async throws -> SpacesFetchResult {
        SpacesFetchResult(records: records,
                          snapshot: SpacesSnapshot(records: records),
                          engineVersion: ZenSpacesReader.supportedEngineVersion,
                          fetchedAt: Date())
    }

    func rename(_ target: RenameTarget, _ name: String) async throws -> SpacesRecord {
        try await Task.sleep(for: .seconds(1))
        let name = try ZenSpacesWriter.validName(name)
        guard let index = records.firstIndex(where: { $0.id == target.id }),
              let raw = records[index].raw,
              let cleartext = try? JSONEncoder().encode(raw)
        else { throw ZenSpacesWriteError.recordNotFound(target.id) }
        let changed = try ZenSpacesWriter.changed(cleartext, id: target.id, kind: target.kind) {
            $0["name"] = .string(name)
        }
        let record = SpacesRecord(id: target.id, modified: Date(), cleartext: changed)
        records[index] = record
        return record
    }

    func pin(_ url: URL, _ title: String, _ spaceUUID: String) async throws -> PinnedTab {
        try await Task.sleep(for: .seconds(1))
        guard let index = records.firstIndex(where: { $0.id == spaceUUID }),
              let raw = records[index].raw,
              let spaceCleartext = try? JSONEncoder().encode(raw)
        else { throw ZenSpacesWriteError.recordNotFound(spaceUUID) }
        let tabID = ZenSpacesWriter.newTabSyncID()
        let tabCleartext = try ZenSpacesWriter.newPinnedTab(id: tabID,
                                                            url: url,
                                                            title: title,
                                                            spaceUUID: spaceUUID,
                                                            containerGuid: raw["data"]?["containerGuid"]?.stringValue)
        let changedSpace = try ZenSpacesWriter.changed(spaceCleartext, id: spaceUUID, kind: "space") { data in
            guard case .array(let children)? = data["children"] else { return }
            data["children"] = .array(children + [.string(tabID)])
        }
        let tab = SpacesRecord(id: tabID, modified: Date(), cleartext: tabCleartext)
        let space = SpacesRecord(id: spaceUUID, modified: Date(), cleartext: changedSpace)
        records.append(tab)
        records[index] = space
        return PinnedTab(tab: tab, space: space)
    }
}
