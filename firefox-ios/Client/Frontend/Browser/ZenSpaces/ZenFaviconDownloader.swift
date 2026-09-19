// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import ZenSpacesKit

/// Fetches a page's real favicon for a new pin. Firefox's own favicon
/// helper falls back to a generated letter image, which must not be synced
/// to Zen as if it were the site's icon, so this downloads it directly and
/// gives up quietly: a pin never waits on or fails because of its icon.
enum ZenFaviconDownloader {
    private static let maxBytes = 256 * 1024

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        return URLSession(configuration: configuration)
    }()

    /// The page's declared icon, then the site's `/favicon.ico`.
    static func dataURL(pageURL: URL, declaredIcon: URL?) async -> String? {
        var candidates = [URL]()
        if let declaredIcon, ["http", "https"].contains(declaredIcon.scheme?.lowercased() ?? "") {
            candidates.append(declaredIcon)
        }
        if let fallback = URL(string: "/favicon.ico", relativeTo: pageURL)?.absoluteURL, !candidates.contains(fallback) {
            candidates.append(fallback)
        }
        for candidate in candidates {
            if let icon = await download(candidate) {
                return icon
            }
        }
        return nil
    }

    private static func download(_ url: URL) async -> String? {
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              data.count <= maxBytes
        else { return nil }
        return FaviconDataURL.encode(data, mimeType: http.mimeType)
    }
}
