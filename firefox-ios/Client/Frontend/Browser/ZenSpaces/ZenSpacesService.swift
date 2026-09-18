// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Account
import ZenSpacesKit

/// The app-wide spaces store, shared by every window.
@MainActor
enum ZenSpacesService {
    static let store = SpacesStore(cache: cache, fetch: fetch)
    static let pinnedTabLinks = PinnedTabLinks()

    private static var cache: SpacesCache {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return SpacesCache(url: directory.appendingPathComponent("ZenSpaces/spaces.json"))
    }

    private static func fetch() async throws -> SpacesFetchResult {
        let auth = try await ZenSpacesAuthProvider(accountManager: RustFirefoxAccounts.shared.accountManager).auth()
        return try await ZenSpacesReader(auth: auth).fetch()
    }
}
