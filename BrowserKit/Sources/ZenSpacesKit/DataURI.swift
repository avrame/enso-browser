// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

/// A decoded RFC 2397 `data:` URL, the form Zen syncs favicons in.
public struct DataURI: Sendable, Equatable {
    public let mediaType: String
    public let data: Data

    public var isSVG: Bool { mediaType == "image/svg+xml" }

    /// Accepts base64 (`data:image/png;base64,…`) and percent-encoded
    /// (`data:image/svg+xml,%3Csvg…` or `;utf8,<svg…`) payloads.
    public init?(_ string: String) {
        guard string.lowercased().hasPrefix("data:"), let comma = string.firstIndex(of: ",") else { return nil }
        let header = string[string.index(string.startIndex, offsetBy: 5)..<comma]
        let payload = String(string[string.index(after: comma)...])
        let parameters = header.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

        let decoded: Data?
        if parameters.contains("base64") {
            decoded = Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
        } else {
            decoded = (payload.removingPercentEncoding ?? payload).data(using: .utf8)
        }
        guard let decoded, !decoded.isEmpty else { return nil }

        let type = parameters.first.flatMap { $0.contains("/") ? $0 : nil }
        mediaType = type ?? "text/plain"
        data = decoded
    }
}
