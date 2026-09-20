// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import WebKit

/// What the user has allowed each extension.
///
/// WebKit keeps an extension's rulesets and storage between launches but
/// not its granted permissions, so the browser has to remember them; an
/// extension would otherwise ask again on every launch.
enum ZenExtensionGrants {
    private struct Grants: Codable {
        var permissions: Set<String> = []
        var patterns: Set<String> = []
    }

    private static let key = "ZenExtensionGrants"

    static func allow(permissions: Set<WKWebExtension.Permission> = [],
                      patterns: Set<WKWebExtension.MatchPattern> = [],
                      for identifier: String) {
        var stored = all()
        var grants = stored[identifier] ?? Grants()
        grants.permissions.formUnion(permissions.map(\.rawValue))
        grants.patterns.formUnion(patterns.map { $0.string })
        stored[identifier] = grants
        save(stored)
    }

    /// Re-applies what the user allowed earlier to a loaded context.
    static func apply(to context: WKWebExtensionContext) {
        guard let grants = all()[context.uniqueIdentifier] else { return }
        for permission in grants.permissions {
            context.setPermissionStatus(.grantedExplicitly, for: WKWebExtension.Permission(rawValue: permission))
        }
        for pattern in grants.patterns {
            guard let pattern = try? WKWebExtension.MatchPattern(string: pattern) else { continue }
            context.setPermissionStatus(.grantedExplicitly, for: pattern)
        }
    }

    static func forget(_ identifier: String) {
        var stored = all()
        stored.removeValue(forKey: identifier)
        save(stored)
    }

    private static func all() -> [String: Grants] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONDecoder().decode([String: Grants].self, from: data)
        else { return [:] }
        return stored
    }

    private static func save(_ stored: [String: Grants]) {
        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
