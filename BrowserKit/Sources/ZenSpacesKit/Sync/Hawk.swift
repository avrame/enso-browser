// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import CryptoKit
import Foundation

/// Hawk request signing, which Sync 1.5 storage requests use with the
/// credentials the tokenserver hands out.
public struct HawkCredentials: Sendable, Equatable {
    public let id: String
    public let key: Data

    public init(id: String, key: Data) {
        self.id = id
        self.key = key
    }
}

public enum Hawk {
    /// Signs a request without a payload hash, which is all a GET needs.
    public static func authorizationHeader(credentials: HawkCredentials,
                                           method: String,
                                           url: URL,
                                           timestamp: Int,
                                           nonce: String,
                                           ext: String? = nil) -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var resource = components?.percentEncodedPath ?? "/"
        if resource.isEmpty { resource = "/" }
        if let query = components?.percentEncodedQuery {
            resource += "?\(query)"
        }
        let host = (url.host ?? "").lowercased()
        let port = url.port ?? (url.scheme?.lowercased() == "http" ? 80 : 443)

        let normalized = [
            "hawk.1.header",
            String(timestamp),
            nonce,
            method.uppercased(),
            resource,
            host,
            String(port),
            "",
            ext ?? "",
        ].joined(separator: "\n") + "\n"

        let mac = HMAC<SHA256>.authenticationCode(for: Data(normalized.utf8),
                                                  using: SymmetricKey(data: credentials.key))
        var header = "Hawk id=\"\(credentials.id)\", ts=\"\(timestamp)\", nonce=\"\(nonce)\""
        if let ext {
            header += ", ext=\"\(ext)\""
        }
        header += ", mac=\"\(Data(mac).base64EncodedString())\""
        return header
    }

    public static func makeNonce() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<8).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64EncodedString()
    }
}
