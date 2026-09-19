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

    // MARK: Pinning

    func testPinCreatesTheTabThenAppendsItToTheSpace() async throws {
        let server = try makeServer(engineVersion: 3)
        let writer = ZenSpacesWriter(auth: try auth(), transport: server, makeTabID: { "1758000000000-abc" })

        let pinned = try await writer.pinTab(url: try XCTUnwrap(URL(string: "https://example.com/a")),
                                             title: "Example",
                                             inSpace: "{a}")

        XCTAssertEqual(server.puts.map(\.id), ["1758000000000-abc", "{a}"], "tab first, then the space")
        XCTAssertEqual(server.puts.first?.ifUnmodifiedSince, "0.00", "the tab must not already exist")
        XCTAssertEqual(server.puts.last?.ifUnmodifiedSince, "1700000000.00")

        let tab = try decrypt(try XCTUnwrap(server.puts.first).payload)
        XCTAssertEqual(tab["kind"], .string("tab"))
        XCTAssertEqual(tab["data"]?["tabId"], .string("1758000000000-abc"))
        XCTAssertEqual(tab["data"]?["url"], .string("https://example.com/a"))
        XCTAssertEqual(tab["data"]?["title"], .string("Example"))
        XCTAssertEqual(tab["data"]?["pinned"], .bool(true))
        XCTAssertEqual(tab["data"]?["essential"], .bool(false))
        XCTAssertEqual(tab["data"]?["workspaceUuid"], .string("{a}"))
        XCTAssertEqual(tab["data"]?["folderId"], .null)
        XCTAssertEqual(tab["data"]?["containerGuid"], .string("builtin-2"), "the space's container")
        XCTAssertEqual(tab["data"]?["defaultContainer"], .bool(true))

        let space = try decrypt(try XCTUnwrap(server.puts.last).payload)
        XCTAssertEqual(space["data"]?["children"],
                       .array([.string("t1"), .string("f1"), .string("1758000000000-abc")]))
        XCTAssertEqual(space["data"]?["name"], .string("Old"), "nothing else changes")
        XCTAssertEqual(space["data"]?["futureField"], .object(["x": .bool(true)]))

        guard case .tab(let record) = pinned.tab.body else { return XCTFail("\(pinned.tab.body)") }
        XCTAssertEqual(record.displayTitle, "Example")
    }

    func testPinKeepsAConcurrentReorderOfTheSpace() async throws {
        let server = try makeServer(engineVersion: 3)
        let reordered = Self.space.replacingOccurrences(of: #""children":["t1","f1"]"#, with: #""children":["f1","t1"]"#)
        server.concurrentEdits = [("{a}", reordered)]
        let writer = ZenSpacesWriter(auth: try auth(), transport: server, makeTabID: { "new" })

        _ = try await writer.pinTab(url: try XCTUnwrap(URL(string: "https://example.com/")), title: "", inSpace: "{a}")

        let space = try decrypt(try XCTUnwrap(server.puts.last).payload)
        XCTAssertEqual(space["data"]?["children"], .array([.string("f1"), .string("t1"), .string("new")]))
        XCTAssertEqual(server.puts.filter { $0.id == "new" }.count, 1, "the tab is written once")
    }

    func testPinCarriesADataURLIconButDropsRemoteOnes() throws {
        let url = try XCTUnwrap(URL(string: "https://a/"))
        func icon(_ icon: String) throws -> JSONValue? {
            let data = try ZenSpacesWriter.newPinnedTab(id: "t",
                                                        url: url,
                                                        title: "A",
                                                        icon: icon,
                                                        spaceUUID: "{a}",
                                                        containerGuid: nil)
            return try JSONDecoder().decode(JSONValue.self, from: data)["data"]?["icon"]
        }
        XCTAssertEqual(try icon("data:image/png;base64,AAAA"), .string("data:image/png;base64,AAAA"))
        XCTAssertEqual(try icon("https://a/favicon.ico"), .string(""))
    }

    func testPinWithoutAContainerLeavesItUnset() throws {
        let data = try ZenSpacesWriter.newPinnedTab(id: "t",
                                                    url: try XCTUnwrap(URL(string: "https://a/")),
                                                    title: "A",
                                                    spaceUUID: "{a}",
                                                    containerGuid: nil)
        let tab = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(tab["data"]?["containerGuid"], .null)
        XCTAssertEqual(tab["data"]?["defaultContainer"], .bool(false))
    }

    func testPinRefusesWithoutWriting() async throws {
        let server = try makeServer(engineVersion: 3)
        let writer = ZenSpacesWriter(auth: try auth(), transport: server)
        struct Case {
            let url: String
            let space: String
            let expected: ZenSpacesWriteError
        }
        let cases = [
            Case(url: "about:blank", space: "{a}", expected: .unpinnableURL("about:blank")),
            Case(url: "https://a/", space: "{gone}", expected: .recordNotFound("{gone}")),
            Case(url: "https://a/", space: "f1", expected: .unexpectedRecord(id: "f1", reason: "not a space")),
        ]
        for test in cases {
            do {
                _ = try await writer.pinTab(url: try XCTUnwrap(URL(string: test.url)), title: "", inSpace: test.space)
                XCTFail("expected \(test.expected)")
            } catch {
                XCTAssertEqual(error as? ZenSpacesWriteError, test.expected)
            }
        }
        XCTAssertTrue(server.puts.isEmpty)

        let newer = try makeServer(engineVersion: 4)
        do {
            _ = try await ZenSpacesWriter(auth: try auth(), transport: newer)
                .pinTab(url: try XCTUnwrap(URL(string: "https://a/")), title: "", inSpace: "{a}")
            XCTFail("expected refusal")
        } catch {
            XCTAssertEqual(error as? ZenSpacesWriteError, .unsupportedEngineVersion(4))
        }
        XCTAssertTrue(newer.puts.isEmpty)
    }

    func testGeneratedIDsFollowZensFormat() {
        let id = ZenSpacesWriter.newTabSyncID()
        XCTAssertNotNil(id.range(of: #"^\d{13}-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#,
                                 options: .regularExpression), id)
    }

    // MARK: Unpinning

    private static let pinnedTab = #"{"id":"t1","kind":"tab","data":{"tabId":"t1","url":"https://a/","#
        + #""pinned":true,"essential":false,"workspaceUuid":"{a}","folderId":null}}"#
    private static let folderTab = #"{"id":"t2","kind":"tab","data":{"tabId":"t2","url":"https://b/","#
        + #""pinned":true,"essential":false,"workspaceUuid":"{a}","folderId":"f1"}}"#

    func testUnpinUpdatesTheSpaceThenWritesTheTombstone() async throws {
        let server = try makeServer(engineVersion: 3)
        let bundle = try XCTUnwrap(collection)
        server.items["t1"] = try server.bso("t1", Self.pinnedTab, bundle, modified: 1_700_000_100)
        let writer = ZenSpacesWriter(auth: try auth(), transport: server)

        let unpinned = try await writer.unpinTab("t1")

        XCTAssertEqual(server.puts.map(\.id), ["{a}", "t1"], "the space first, the tombstone last")
        let space = try decrypt(try XCTUnwrap(server.puts.first).payload)
        XCTAssertEqual(space["data"]?["children"], .array([.string("f1")]))
        XCTAssertEqual(space["data"]?["futureField"], .object(["x": .bool(true)]), "nothing else changes")
        let tombstone = try decrypt(try XCTUnwrap(server.puts.last).payload)
        XCTAssertEqual(tombstone, .object(["id": .string("t1"), "deleted": .bool(true)]))
        XCTAssertEqual(server.puts.last?.ifUnmodifiedSince, "1700000100.00", "only if the tab is unchanged")
        XCTAssertEqual(unpinned.tombstone.body, .tombstone)
    }

    func testUnpinFromAFolderEditsTheFolder() async throws {
        let server = try makeServer(engineVersion: 3)
        let bundle = try XCTUnwrap(collection)
        let folder = Self.liveFolder.replacingOccurrences(of: #""children":["t1","sp1"]"#,
                                                          with: #""children":["t2","sp1"]"#)
        server.items["f1"] = try server.bso("f1", folder, bundle)
        server.items["t2"] = try server.bso("t2", Self.folderTab, bundle)
        let writer = ZenSpacesWriter(auth: try auth(), transport: server)

        _ = try await writer.unpinTab("t2")

        XCTAssertEqual(server.puts.map(\.id), ["f1", "t2"])
        let updated = try decrypt(try XCTUnwrap(server.puts.first).payload)
        XCTAssertEqual(updated["data"]?["children"], .array([.string("sp1")]))
        XCTAssertEqual(updated["data"]?["live"]?["type"], .string("rss"), "the live feed is kept")
    }

    func testUnpinRefusesWithoutWriting() async throws {
        let server = try makeServer(engineVersion: 3)
        let bundle = try XCTUnwrap(collection)
        func tab(_ id: String, _ replacing: String, _ with: String) -> String {
            Self.pinnedTab.replacingOccurrences(of: "\"t1\"", with: "\"\(id)\"")
                .replacingOccurrences(of: replacing, with: with)
        }
        server.items["e1"] = try server.bso("e1", tab("e1", #""essential":false"#, #""essential":true"#), bundle)
        server.items["n1"] = try server.bso("n1", tab("n1", #""pinned":true"#, #""pinned":false"#), bundle)
        server.items["t5"] = try server.bso("t5", tab("t5", "", ""), bundle)
        server.items["gone"] = try server.bso("gone", #"{"id":"gone","deleted":true}"#, bundle)
        let writer = ZenSpacesWriter(auth: try auth(), transport: server)

        struct Case {
            let id: String
            let expected: ZenSpacesWriteError
        }
        let cases = [
            Case(id: "e1", expected: .unexpectedRecord(id: "e1", reason: "an Essential")),
            Case(id: "n1", expected: .unexpectedRecord(id: "n1", reason: "not pinned")),
            Case(id: "t5", expected: .unexpectedRecord(id: "t5",
                                                       reason: "not listed in its space; it may be in a split view")),
            Case(id: "f1", expected: .unexpectedRecord(id: "f1", reason: "not a tab")),
            Case(id: "gone", expected: .recordNotFound("gone")),
            Case(id: "missing", expected: .recordNotFound("missing")),
        ]
        for test in cases {
            do {
                _ = try await writer.unpinTab(test.id)
                XCTFail("expected \(test.expected)")
            } catch {
                XCTAssertEqual(error as? ZenSpacesWriteError, test.expected)
            }
        }
        XCTAssertTrue(server.puts.isEmpty, "nothing is written when refused")
    }

    func testUnpinKeepsAConcurrentReorderAndRetriesTheTombstone() async throws {
        let server = try makeServer(engineVersion: 3)
        let bundle = try XCTUnwrap(collection)
        server.items["t1"] = try server.bso("t1", Self.pinnedTab, bundle)
        let reordered = Self.space.replacingOccurrences(of: #""children":["t1","f1"]"#,
                                                        with: #""children":["f1","t1","t9"]"#)
        let retitled = Self.pinnedTab.replacingOccurrences(of: #""url":"https://a/""#,
                                                           with: #""url":"https://a/","title":"New""#)
        server.concurrentEdits = [("{a}", reordered), ("t1", retitled)]
        let writer = ZenSpacesWriter(auth: try auth(), transport: server)

        _ = try await writer.unpinTab("t1")

        let space = try decrypt(try XCTUnwrap(server.puts.last { $0.id == "{a}" }).payload)
        XCTAssertEqual(space["data"]?["children"], .array([.string("f1"), .string("t9")]))
        let tombstone = try decrypt(try XCTUnwrap(server.puts.last).payload)
        XCTAssertEqual(tombstone["deleted"], .bool(true))
        XCTAssertEqual(server.puts.filter { $0.id == "t1" }.count, 2, "retried after the tab changed")
    }

    func testUnpinRefusesOtherEngineVersions() async throws {
        let server = try makeServer(engineVersion: 4)
        do {
            _ = try await ZenSpacesWriter(auth: try auth(), transport: server).unpinTab("t1")
            XCTFail("expected refusal")
        } catch {
            XCTAssertEqual(error as? ZenSpacesWriteError, .unsupportedEngineVersion(4))
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
