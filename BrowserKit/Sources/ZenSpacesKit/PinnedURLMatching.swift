// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

/// Decides whether an open tab already shows a pinned tab's page, so
/// tapping a pinned tab reuses it instead of opening a duplicate.
public enum PinnedURLMatching {
    /// Same scheme, host (ignoring case and a leading `www.`), path
    /// (ignoring a trailing slash) and query. The fragment is ignored.
    public static func isSamePage(_ lhs: URL, _ rhs: URL) -> Bool {
        key(lhs) == key(rhs)
    }

    private static func key(_ url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var host = components.host?.lowercased() ?? ""
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        var path = components.percentEncodedPath
        while path.hasSuffix("/") {
            path.removeLast()
        }
        let scheme = components.scheme?.lowercased() ?? ""
        let port = components.port.map { ":\($0)" } ?? ""
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)\(path)\(query)"
    }
}
