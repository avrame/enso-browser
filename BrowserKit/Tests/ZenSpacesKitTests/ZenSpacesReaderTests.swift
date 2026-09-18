// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

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
