// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

/// Remembers which browser tab each Zen pinned tab opened, across launches,
/// the way Zen keeps a pinned tab bound to one tab. Keys are Zen tab sync
/// ids; values are browser tab UUIDs, which tab restoration preserves.
public final class PinnedTabLinks: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard, key: String = "zenSpaces.pinnedTabLinks") {
        self.defaults = defaults
        self.key = key
    }

    /// The linked browser tab, if `isOpen` confirms it still exists; a link
    /// to a closed tab is forgotten.
    public func browserTab(for pinnedTabId: String, isOpen: (String) -> Bool) -> String? {
        lock.withLock {
            var links = load()
            guard let uuid = links[pinnedTabId] else { return nil }
            if isOpen(uuid) { return uuid }
            links[pinnedTabId] = nil
            save(links)
            return nil
        }
    }

    /// A browser tab belongs to at most one pinned tab, so linking it
    /// releases any other pinned tab that pointed at it.
    public func link(_ pinnedTabId: String, to browserTab: String) {
        lock.withLock {
            var links = load().filter { $0.value != browserTab }
            links[pinnedTabId] = browserTab
            save(links)
        }
    }

    private func load() -> [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    private func save(_ links: [String: String]) {
        defaults.set(links, forKey: key)
    }
}
