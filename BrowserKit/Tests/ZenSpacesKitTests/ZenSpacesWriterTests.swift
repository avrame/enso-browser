// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest
@testable import ZenSpacesKit

final class ZenSpacesWriterTests: XCTestCase {
    private let syncKeyBytes = Data((0..<64).map { UInt8($0) })
    private let collection = try? KeyBundle(encryptionKey: Data(repeating: 7, count: 32),
                                            hmacKey: Data(repeating: 9, count: 32))
    private static let space = #"{"id":"{a}","kind":"space","data":{"uuid":"{a}","name":"Old","icon":"🏠","#
        + #""theme":{"type":"gradient","gradientColors":[{"c":[1,2,3],"isCustom":false}],"opacity":0.5,"texture":0},"#
        + #""containerGuid":"builtin-2","children":["t1","f1"],"futureField":{"x":true}},"extra":"kept"}"#

    private static let liveFolder = #"{"id":"f1","kind":"folder","data":{"folderId":"f1","name":"Feeds","#
        + #""icon":null,"workspaceUuid":"{a}","parentFolderId":null,"#
        + #""live":{"type":"rss","state":{"url":"https://example.com/feed.xml","maxItems":10}},"#
        + #""children":["t1","sp1"]}}"#

    // MARK: Encryption

    func testEncryptMatchesOpenSSLVector() throws {
        // Same vector as SyncCryptoTests, produced with `openssl enc` and `openssl dgst`.
        let bundle = try KeyBundle(encryptionKey: Data(0x00...0x1f), hmacKey: Data(0x20...0x3f))
        let cleartext = Data(#"{"id":"layout","kind":"layout","data":{"spaces":["s1"],"essentials":{}}}"#.utf8)
        let payload = try bundle.encrypt(cleartext, iv: Data(0xa0...0xaf))
        XCTAssertEqual(payload.ciphertext, "ppP/DT+lpfigXBnc6BZSbcN68QOwpHlxB2bGPghNUpC4t/gzF+tWuZDw4eT8Ux6/"
            + "dclGXPdv5VDwsR1KjMViwi0R8woCQ0BiAggC04UUdSI=")
        XCTAssertEqual(payload.hmac, "bd5b1beac7973cbb9a618fc8e5d4b230503be499cd33085f643997277c9b017f")
    }

    func testEncryptUsesFreshIVs() throws {
        let bundle = try XCTUnwrap(collection)
        let first = try bundle.encrypt(Data("same".utf8))
        let second = try bundle.encrypt(Data("same".utf8))
        XCTAssertNotEqual(first.iv, second.iv)
        XCTAssertEqual(try bundle.decrypt(second), Data("same".utf8))
    }

    // MARK: Record changes

    func testChangeKeepsEveryOtherField() throws {
        let changed = try ZenSpacesWriter.changed(Data(Self.space.utf8), id: "{a}", kind: "space") {
            $0["name"] = .string("New")
        }
        let before = try JSONDecoder().decode(JSONValue.self, from: Data(Self.space.utf8))
        let after = try JSONDecoder().decode(JSONValue.self, from: changed)

        XCTAssertEqual(after["data"]?["name"], .string("New"))
        guard case .object(var afterData)? = after["data"], case .object(var beforeData)? = before["data"] else {
            return XCTFail("data missing")
        }
        afterData["name"] = nil
        beforeData["name"] = nil
        XCTAssertEqual(afterData, beforeData, "only the name may change")
        XCTAssertEqual(after["extra"], .string("kept"))
        XCTAssertEqual(after["kind"], .string("space"))
    }

    func testChangeRefusesTheWrongRecord() {
        let tab = Data(#"{"id":"{a}","kind":"tab","data":{"tabId":"{a}","url":"https://a/"}}"#.utf8)
        XCTAssertThrowsError(try ZenSpacesWriter.changed(tab, id: "{a}", kind: "space") { _ in }) {
            XCTAssertEqual($0 as? ZenSpacesWriteError, .unexpectedRecord(id: "{a}", reason: "not a space"))
        }
        let deleted = Data(#"{"id":"{a}","deleted":true}"#.utf8)
        XCTAssertThrowsError(try ZenSpacesWriter.changed(deleted, id: "{a}", kind: "space") { _ in }) {
            XCTAssertEqual($0 as? ZenSpacesWriteError, .recordNotFound("{a}"))
        }
        XCTAssertThrowsError(try ZenSpacesWriter.changed(Data(Self.space.utf8), id: "{b}", kind: "space") { _ in }) {
            XCTAssertEqual($0 as? ZenSpacesWriteError, .unexpectedRecord(id: "{b}", reason: "id does not match"))
        }
    }

    // MARK: Server round trips

    func testRenameWritesConditionallyAndOnlyTheName() async throws {
        let server = try makeServer(engineVersion: 3)
        let writer = ZenSpacesWriter(auth: try auth(), transport: server)

        let record = try await writer.rename(.space("{a}"), to: "  New name  ")

        let put = try XCTUnwrap(server.puts.first)
        XCTAssertEqual(server.puts.count, 1)
        XCTAssertEqual(put.ifUnmodifiedSince, "1700000000.00")
        let request = try XCTUnwrap(server.requests.last)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Hawk ") == true)

        let uploaded = try decrypt(put.payload)
        XCTAssertEqual(uploaded["data"]?["name"], .string("New name"))
        XCTAssertEqual(uploaded["data"]?["futureField"], .object(["x": .bool(true)]))
        XCTAssertEqual(uploaded["data"]?["children"], .array([.string("t1"), .string("f1")]))
        guard case .space(let space) = record.body else { return XCTFail("\(record.body)") }
        XCTAssertEqual(space.name, "New name")
        XCTAssertEqual(record.modified, Date(timeIntervalSince1970: 1_700_000_010))
    }

    func testConcurrentEditIsReReadAndKept() async throws {
        let server = try makeServer(engineVersion: 3)
        let reordered = #""children":["f1","t1","t2"]"#
        let edited = Self.space.replacingOccurrences(of: #""children":["t1","f1"]"#, with: reordered)
        server.concurrentEdits = [("{a}", edited)]
        let writer = ZenSpacesWriter(auth: try auth(), transport: server)

        _ = try await writer.rename(.space("{a}"), to: "New")

        XCTAssertEqual(server.puts.map(\.ifUnmodifiedSince), ["1700000000.00", "1700000005.00"])
        let uploaded = try decrypt(try XCTUnwrap(server.puts.last).payload)
        XCTAssertEqual(uploaded["data"]?["name"], .string("New"))
        let children = JSONValue.array([.string("f1"), .string("t1"), .string("t2")])
        XCTAssertEqual(uploaded["data"]?["children"], children, "the other device's reordering survives")
    }

    func testRenamesAFolderKeepingItsLiveFeedAndChildren() async throws {
        let server = try makeServer(engineVersion: 3)
        let writer = ZenSpacesWriter(auth: try auth(), transport: server)

        let record = try await writer.rename(.folder("f1"), to: "News")

        let put = try XCTUnwrap(server.puts.first)
        XCTAssertEqual(put.id, "f1")
        let before = try JSONDecoder().decode(JSONValue.self, from: Data(Self.liveFolder.utf8))
        let uploaded = try decrypt(put.payload)
        XCTAssertEqual(uploaded["data"]?["name"], .string("News"))
        XCTAssertEqual(uploaded["data"]?["live"], before["data"]?["live"])
        XCTAssertEqual(uploaded["data"]?["children"], before["data"]?["children"])
        XCTAssertEqual(uploaded["data"]?["workspaceUuid"], .string("{a}"))
        guard case .folder(let folder) = record.body else { return XCTFail("\(record.body)") }
        XCTAssertEqual(folder.name, "News")
    }

    func testRefusesToRenameARecordOfAnotherKind() async throws {
        let server = try makeServer(engineVersion: 3)
        let writer = ZenSpacesWriter(auth: try auth(), transport: server)
        do {
            _ = try await writer.rename(.folder("{a}"), to: "New")
            XCTFail("a space must not be renamed as a folder")
        } catch {
            XCTAssertEqual(error as? ZenSpacesWriteError, .unexpectedRecord(id: "{a}", reason: "not a folder"))
        }
        XCTAssertTrue(server.puts.isEmpty)
    }

    func testGivesUpAfterRepeatedConflicts() async throws {
        let server = try makeServer(engineVersion: 3)
        server.concurrentEdits = Array(repeating: ("{a}", Self.space), count: 3)
        let writer = ZenSpacesWriter(auth: try auth(), transport: server)

        do {
            _ = try await writer.rename(.space("{a}"), to: "New")
            XCTFail("expected a conflict")
        } catch {
            XCTAssertEqual(error as? ZenSpacesWriteError, .conflict("{a}"))
        }
        XCTAssertEqual(server.puts.count, 3)
    }

    func testRefusesOtherEngineVersionsWithoutWriting() async throws {
        for version in [2, 4, nil] as [Int?] {
            let server = try makeServer(engineVersion: version)
            let writer = ZenSpacesWriter(auth: try auth(), transport: server)
            do {
                _ = try await writer.rename(.space("{a}"), to: "New")
                XCTFail("expected refusal for \(String(describing: version))")
            } catch {
                XCTAssertEqual(error as? ZenSpacesWriteError, .unsupportedEngineVersion(version))
            }
            XCTAssertTrue(server.puts.isEmpty)
        }
    }

    func testRejectsEmptyNamesAndMissingSpaces() async throws {
        let server = try makeServer(engineVersion: 3)
        let writer = ZenSpacesWriter(auth: try auth(), transport: server)
        do {
            _ = try await writer.rename(.space("{a}"), to: "   ")
            XCTFail("expected refusal")
        } catch {
            XCTAssertEqual(error as? ZenSpacesWriteError, .invalidName)
        }
        do {
            _ = try await writer.rename(.space("{gone}"), to: "New")
            XCTFail("expected not found")
        } catch {
            XCTAssertEqual(error as? ZenSpacesWriteError, .recordNotFound("{gone}"))
        }
        XCTAssertTrue(server.puts.isEmpty)
    }

    // MARK: Helpers

    private func makeServer(engineVersion: Int?) throws -> FakeSyncServer {
        let server = try FakeSyncServer(engineVersion: engineVersion)
        let bundle = try XCTUnwrap(collection)
        try server.putKeys(encryptedWith: try KeyBundle(encryptionKey: syncKeyBytes.prefix(32),
                                                        hmacKey: syncKeyBytes.suffix(32)),
                           collectionBundle: bundle)
        server.items["{a}"] = try server.bso("{a}", Self.space, bundle)
        server.items["f1"] = try server.bso("f1", Self.liveFolder, bundle)
        return server
    }

    private func decrypt(_ payload: String) throws -> JSONValue {
        let envelope = try JSONDecoder().decode(EncryptedPayload.self, from: Data(payload.utf8))
        return try JSONDecoder().decode(JSONValue.self, from: try XCTUnwrap(collection).decrypt(envelope))
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
}
