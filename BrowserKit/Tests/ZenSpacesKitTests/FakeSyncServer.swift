// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import CommonCrypto
import CryptoKit
import XCTest
@testable import ZenSpacesKit

/// Serves the tokenserver and the Sync storage endpoints ZenSpacesKit uses.
/// Encrypts with CommonCrypto directly, independently of `KeyBundle`.
final class FakeSyncServer: HTTPTransport, @unchecked Sendable {
    struct Put {
        let id: String
        let payload: String
        let ifUnmodifiedSince: String?
    }

    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private var recordedPuts: [Put] = []
    private let metaGlobal: String
    private var keysBSO: BSO?
    var pages: [[BSO]] = []
    /// Single records by id, for GET and PUT of `storage/spaces/<id>`.
    var items: [String: BSO] = [:]
    /// Each pending entry makes the next PUT find the record changed by
    /// "another device" (applied, then answered with 412).
    var concurrentEdits: [(id: String, cleartext: String)] = []
    var collectionBundle: KeyBundle?

    var requests: [URLRequest] { lock.withLock { recorded } }
    var puts: [Put] { lock.withLock { recordedPuts } }

    init(engineVersion: Int?) throws {
        let engines: [String: Any] = engineVersion.map { ["spaces": ["version": $0, "syncID": "abc"]] } ?? [:]
        let payload = try JSONSerialization.data(withJSONObject: ["storageVersion": 5, "engines": engines])
        metaGlobal = String(decoding: payload, as: UTF8.self)
    }

    func putKeys(encryptedWith syncBundle: KeyBundle, collectionBundle: KeyBundle) throws {
        self.collectionBundle = collectionBundle
        let keys = try JSONSerialization.data(withJSONObject: [
            "id": "keys", "collection": "crypto",
            "default": [collectionBundle.encryptionKey.base64EncodedString(),
                        collectionBundle.hmacKey.base64EncodedString()],
        ])
        keysBSO = BSO(id: "keys", modified: 1, payload: try Self.encrypt(keys, syncBundle))
    }

    func bso(_ id: String, _ cleartext: String, _ bundle: KeyBundle, modified: Double = 1_700_000_000) throws -> BSO {
        BSO(id: id, modified: modified, payload: try Self.encrypt(Data(cleartext.utf8), bundle))
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { recorded.append(request) }
        let url = try XCTUnwrap(request.url)
        if url.host == "token.example" {
            let token = #"{"id":"hawk-id","key":"hawk-key","api_endpoint":"https://storage.example/1.5/42","#
                + #""uid":42,"duration":3600}"#
            return respond(url, token, headers: ["X-Timestamp": "1700000000.25"])
        }
        let itemPrefix = "/1.5/42/storage/spaces/"
        switch url.path {
        case "/1.5/42/storage/meta/global":
            return respond(url, try json(BSO(id: "global", modified: 1, payload: metaGlobal)))
        case "/1.5/42/storage/crypto/keys":
            return respond(url, try json(try XCTUnwrap(keysBSO)))
        case "/1.5/42/storage/spaces":
            let second = url.query?.contains("offset=page-2") == true
            let page = second ? pages.last ?? [] : pages.first ?? []
            let headers = (!second && pages.count > 1) ? ["X-Weave-Next-Offset": "page-2"] : [:]
            return respond(url, try json(page), headers: headers)
        case let path where path.hasPrefix(itemPrefix):
            let id = String(path.dropFirst(itemPrefix.count))
            return request.httpMethod == "PUT" ? try put(id, request, url) : try get(id, url)
        default:
            return respond(url, "{}", status: 404)
        }
    }

    private func get(_ id: String, _ url: URL) throws -> (Data, HTTPURLResponse) {
        guard let item = lock.withLock({ items[id] }) else { return respond(url, "{}", status: 404) }
        return respond(url, try json(item))
    }

    private func put(_ id: String, _ request: URLRequest, _ url: URL) throws -> (Data, HTTPURLResponse) {
        let body = try XCTUnwrap(request.httpBody)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        let condition = request.value(forHTTPHeaderField: "X-If-Unmodified-Since")

        return try lock.withLock {
            recordedPuts.append(Put(id: id, payload: fields["payload"] ?? "", ifUnmodifiedSince: condition))
            let current = items[id]
            if let edit = concurrentEdits.first, edit.id == id, let current, let bundle = collectionBundle {
                concurrentEdits.removeFirst()
                items[id] = try bso(id, edit.cleartext, bundle, modified: current.modified + 5)
                return respond(url, "{}", status: 412)
            }
            if let condition, let since = Double(condition), let current, current.modified > since {
                return respond(url, "{}", status: 412)
            }
            let modified = (current?.modified ?? 1_700_000_000) + 10
            items[id] = BSO(id: id, modified: modified, payload: fields["payload"] ?? "")
            let stamp = SyncStorageClient.timestamp(modified)
            return respond(url, stamp, headers: ["X-Last-Modified": stamp])
        }
    }

    private func respond(_ url: URL,
                         _ body: String,
                         status: Int = 200,
                         headers: [String: String] = [:]) -> (Data, HTTPURLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    static func encrypt(_ plaintext: Data, _ bundle: KeyBundle) throws -> String {
        let iv = Data(repeating: 0x42, count: 16)
        var output = Data(count: plaintext.count + kCCBlockSizeAES128)
        let capacity = output.count
        var written = 0
        let status = output.withUnsafeMutableBytes { out in
            plaintext.withUnsafeBytes { input in
                iv.withUnsafeBytes { ivBytes in
                    bundle.encryptionKey.withUnsafeBytes { key in
                        CCCrypt(CCOperation(kCCEncrypt),
                                CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(kCCOptionPKCS7Padding),
                                key.baseAddress,
                                32,
                                ivBytes.baseAddress,
                                input.baseAddress,
                                plaintext.count,
                                out.baseAddress,
                                capacity,
                                &written)
                    }
                }
            }
        }
        XCTAssertEqual(status, CCCryptorStatus(kCCSuccess))
        let ciphertext = output.prefix(written).base64EncodedString()
        let mac = HMAC<SHA256>.authenticationCode(for: Data(ciphertext.utf8), using: SymmetricKey(data: bundle.hmacKey))
        let envelope = ["ciphertext": ciphertext,
                        "IV": iv.base64EncodedString(),
                        "hmac": Data(mac).map { String(format: "%02x", $0) }.joined()]
        return String(decoding: try JSONSerialization.data(withJSONObject: envelope), as: UTF8.self)
    }
}

extension BSO: Encodable {
    private enum EncodingKeys: String, CodingKey { case id, modified, payload }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: EncodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(modified, forKey: .modified)
        try container.encode(payload, forKey: .payload)
    }
}
