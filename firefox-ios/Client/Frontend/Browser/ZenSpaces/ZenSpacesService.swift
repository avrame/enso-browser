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
            return SpacesStore(cache: SpacesCache(url: directory.appendingPathComponent("demo.json")),
                               fetch: { demo(spaceCount: count) })
        }
        #endif
        return SpacesStore(cache: SpacesCache(url: directory.appendingPathComponent("spaces.json")), fetch: fetch)
    }

    private static func fetch() async throws -> SpacesFetchResult {
        let auth = try await ZenSpacesAuthProvider(accountManager: RustFirefoxAccounts.shared.accountManager).auth()
        return try await ZenSpacesReader(auth: auth).fetch()
    }

    private static func demo(spaceCount: Int) -> SpacesFetchResult {
        let records = SpacesDemoData.records(spaceCount: spaceCount)
        return SpacesFetchResult(records: records,
                                 snapshot: SpacesSnapshot(records: records),
                                 engineVersion: ZenSpacesReader.supportedEngineVersion,
                                 fetchedAt: Date())
    }
}
