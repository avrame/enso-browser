// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import CommonCrypto
import CryptoKit
import XCTest
@testable import ZenSpacesKit

final class ZenSpacesReaderTests: XCTestCase {
    private let syncKeyBytes = Data((0..<64).map { UInt8($0) })
    private let collectionEnc = Data(repeating: 7, count: 32)
    private let collectionMac = Data(repeating: 9, count: 32)

    private static let layoutJSON = #"{"id":"layout","kind":"layout","data":{"spaces":["{a}"],"essentials":{}}}"#
    private static let spaceJSON = #"{"id":"{a}","kind":"space","data":{"uuid":"{a}","name":"Alpha","children":["t1"]}}"#
    private static let tabJSON = #"{"id":"t1","kind":"tab","data":"#
        + #"{"tabId":"t1","url":"https://one/","title":"One","workspaceUuid":"{a}"}}"#

    func testReadsCollectionEndToEnd() async throws {
        let server = try FakeSyncServer(engineVersion: 3)
        try server.putKeys(encryptedWith: syncBundle(), collectionBundle: collectionBundle())
        let bundle = try collectionBundle()
        server.pages = [
            [
                try server.bso("layout", Self.layoutJSON, bundle),
                try server.bso("{a}", Self.spaceJSON, bundle),
            ],
            [
                try server.bso("t1", Self.tabJSON, bundle),
                BSO(id: "bad", modified: 1, payload: #"{"ciphertext":"AAAA","IV":"AAAA","hmac":"00"}"#),
            ],
        ]

        let result = try await ZenSpacesReader(auth: auth(), transport: server).fetch()

        XCTAssertEqual(result.engineVersion, 3)
        XCTAssertEqual(result.snapshot.spaces.map(\.record.name), ["Alpha"])
        XCTAssertEqual(result.snapshot.spaces.first?.items.count, 1)
        guard case .malformed = result.records.first(where: { $0.id == "bad" })?.body else {
            return XCTFail("undecryptable record should be reported, not thrown")
        }

        let requests = server.requests
        let tokenRequest = try XCTUnwrap(requests.first)
        XCTAssertEqual(tokenRequest.url?.absoluteString, "https://token.example/1.0/sync/1.5")
        XCTAssertEqual(tokenRequest.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(tokenRequest.value(forHTTPHeaderField: "X-KeyID"), "1234-kid")
        let tokenFetches = requests.filter { $0.url?.path.hasSuffix("/1.0/sync/1.5") == true }
        XCTAssertEqual(tokenFetches.count, 1, "the token is fetched once and reused")
        for request in requests.dropFirst() {
            XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix(#"Hawk id="hawk-id""#) == true)
            XCTAssertEqual(request.httpMethod, "GET")
        }
        XCTAssertTrue(requests.contains { $0.url?.query?.contains("offset=page-2") == true },
                      "follows X-Weave-Next-Offset")
    }

    func testRefusesNewerEngineVersion() async throws {
        let server = try FakeSyncServer(engineVersion: 4)
        do {
            _ = try await ZenSpacesReader(auth: auth(), transport: server).fetch()
            XCTFail("expected refusal")
        } catch {
            XCTAssertEqual(error as? ZenSpacesError, .engineVersionTooNew(4))
        }
    }

    func testReportsMissingEngine() async throws {
        let server = try FakeSyncServer(engineVersion: nil)
        do {
            _ = try await ZenSpacesReader(auth: auth(), transport: server).fetch()
            XCTFail("expected refusal")
        } catch {
            XCTAssertEqual(error as? ZenSpacesError, .engineNotOnServer)
        }
    }

    private func auth() throws -> SyncAuth {
        let k = syncKeyBytes.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return SyncAuth(accessToken: "access-token",
                        keyID: "1234-kid",
                        syncKey: k,
                        tokenServerURL: try XCTUnwrap(URL(string: "https://token.example/")))
    }

    private func syncBundle() throws -> KeyBundle {
        try KeyBundle(encryptionKey: syncKeyBytes.prefix(32), hmacKey: syncKeyBytes.suffix(32))
    }

    private func collectionBundle() throws -> KeyBundle {
        try KeyBundle(encryptionKey: collectionEnc, hmacKey: collectionMac)
    }
}

/// Serves the tokenserver and the storage endpoints the reader touches.
private final class FakeSyncServer: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private let metaGlobal: String
    private var keysBSO: BSO?
    var pages: [[BSO]] = []

    var requests: [URLRequest] { lock.withLock { recorded } }

    init(engineVersion: Int?) throws {
        let engines: [String: Any] = engineVersion.map { ["spaces": ["version": $0, "syncID": "abc"]] } ?? [:]
        let payload = try JSONSerialization.data(withJSONObject: ["storageVersion": 5, "engines": engines])
        metaGlobal = String(decoding: payload, as: UTF8.self)
    }

    func putKeys(encryptedWith syncBundle: KeyBundle, collectionBundle: KeyBundle) throws {
        let keys = try JSONSerialization.data(withJSONObject: [
            "id": "keys", "collection": "crypto",
            "default": [collectionBundle.encryptionKey.base64EncodedString(),
                        collectionBundle.hmacKey.base64EncodedString()],
        ])
        keysBSO = BSO(id: "keys", modified: 1, payload: try encrypt(keys, syncBundle))
    }

    func bso(_ id: String, _ cleartext: String, _ bundle: KeyBundle) throws -> BSO {
        BSO(id: id, modified: 1_700_000_000, payload: try encrypt(Data(cleartext.utf8), bundle))
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { recorded.append(request) }
        let url = try XCTUnwrap(request.url)
        if url.host == "token.example" {
            let token = #"{"id":"hawk-id","key":"hawk-key","api_endpoint":"https://storage.example/1.5/42","uid":42,"duration":3600}"#
            return respond(url, token, headers: ["X-Timestamp": "1700000000.25"])
        }
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
        default:
            return respond(url, "{}", status: 404)
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

    private func encrypt(_ plaintext: Data, _ bundle: KeyBundle) throws -> String {
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
