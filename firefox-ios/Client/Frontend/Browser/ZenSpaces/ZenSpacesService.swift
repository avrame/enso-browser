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
                               rename: demo.rename)
        }
        #endif
        return SpacesStore(cache: SpacesCache(url: directory.appendingPathComponent("spaces.json")),
                           fetch: fetch,
                           rename: rename)
    }

    private static func fetch() async throws -> SpacesFetchResult {
        try await ZenSpacesReader(auth: auth()).fetch()
    }

    private static func rename(_ uuid: String, _ name: String) async throws -> SpacesRecord {
        try await ZenSpacesWriter(auth: auth()).renameSpace(uuid: uuid, to: name)
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

    func rename(_ uuid: String, _ name: String) async throws -> SpacesRecord {
        try await Task.sleep(for: .seconds(1))
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ZenSpacesWriteError.invalidName }
        guard let index = records.firstIndex(where: { $0.id == uuid }),
              let raw = records[index].raw,
              let cleartext = try? JSONEncoder().encode(raw)
        else { throw ZenSpacesWriteError.recordNotFound(uuid) }
        let changed = try ZenSpacesWriter.changed(cleartext, id: uuid, kind: "space") { $0["name"] = .string(name) }
        let record = SpacesRecord(id: uuid, modified: Date(), cleartext: changed)
        records[index] = record
        return record
    }
}
