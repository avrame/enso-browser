// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest
@testable import ZenSpacesKit

final class SpacesRecordTests: XCTestCase {
    func testDecodesTabWithNullOptionals() {
        let record = decode(#"""
        {"id":"t1","kind":"tab","data":{"tabId":"t1","url":"https://example.com/","title":"Example",
         "icon":"","containerGuid":null,"essential":false,"pinned":true,"workspaceUuid":"{s1}",
         "folderId":null,"staticLabel":null,"hasStaticIcon":false,"defaultContainer":false}}
        """#)
        guard case .tab(let tab) = record.body else { return XCTFail("\(record.body)") }
        XCTAssertEqual(tab.url, "https://example.com/")
        XCTAssertNil(tab.containerGuid)
        XCTAssertNil(tab.folderId)
        XCTAssertEqual(tab.displayTitle, "Example")
    }

    func testStaticLabelWinsOverTitle() {
        let record = decode(#"{"id":"t1","kind":"tab","data":{"tabId":"t1","url":"https://a/","title":"A","staticLabel":"Mine"}}"#)
        guard case .tab(let tab) = record.body else { return XCTFail("\(record.body)") }
        XCTAssertEqual(tab.displayTitle, "Mine")
    }

    func testTombstone() {
        XCTAssertEqual(decode(#"{"id":"x","deleted":true}"#).body, .tombstone)
    }

    func testUnknownKindIsKeptNotRejected() {
        let record = decode(#"{"id":"x","kind":"widget","data":{"a":1}}"#)
        XCTAssertEqual(record.body, .unknown(kind: "widget"))
        XCTAssertEqual(record.raw?["data"]?["a"], .number(1))
    }

    func testMissingRequiredFieldIsMalformed() {
        XCTAssertEqual(decode(#"{"id":"t1","kind":"tab","data":{"tabId":"t1"}}"#).body,
                       .malformed(reason: "tab without url"))
    }

    func testKeepsSpaceThemeVerbatim() {
        let record = decode(#"""
        {"id":"{s1}","kind":"space","data":{"uuid":"{s1}","name":"Work","icon":null,
         "theme":{"type":"gradient","gradientColors":[],"opacity":0.5,"texture":0},
         "containerGuid":"builtin-2","children":[]}}
        """#)
        guard case .space(let space) = record.body else { return XCTFail("\(record.body)") }
        XCTAssertEqual(space.theme?["opacity"], .number(0.5))
        XCTAssertEqual(space.containerGuid, "builtin-2")
    }

    private func decode(_ json: String) -> SpacesRecord {
        let id = (try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))?["id"]?.stringValue ?? ""
        return SpacesRecord(id: id, modified: Date(timeIntervalSince1970: 0), cleartext: Data(json.utf8))
    }
}

final class SpacesSnapshotTests: XCTestCase {
    func testBuildsOrderedTreeFromParents() {
        let snapshot = SpacesSnapshot(records: [
            space("{b}", "Beta", children: []),
            space("{a}", "Alpha", children: ["t1", "f1", "sp1"]),
            folder("f1", "Reading", space: "{a}", children: ["f2", "t2"]),
            folder("f2", "Nested", space: "{a}", parent: "f1", children: ["t3"]),
            tab("t1", space: "{a}"),
            tab("t2", space: "{a}", folder: "f1"),
            tab("t3", space: "{a}", folder: "f2"),
            tab("t4", space: "{a}"),
            tab("t5", space: "{a}"),
            split("sp1", tabs: ["t4", "t5"], space: "{a}"),
            layout(spaces: ["{a}", "{b}"], essentials: [:]),
        ])

        XCTAssertEqual(snapshot.spaces.map(\.record.name), ["Alpha", "Beta"])
        XCTAssertEqual(outline(snapshot.spaces[0].items),
                       ["tab t1", "folder f1", "  folder f2", "    tab t3", "  tab t2", "split sp1 [t4, t5]"])
        XCTAssertEqual(snapshot.issues, [])
    }

    func testSpacesMissingFromLayoutGoLastByName() {
        let snapshot = SpacesSnapshot(records: [
            space("{c}", "Gamma", children: []),
            space("{b}", "Beta", children: []),
            space("{a}", "Alpha", children: []),
            layout(spaces: ["{c}"], essentials: [:]),
        ])
        XCTAssertEqual(snapshot.spaces.map(\.record.name), ["Gamma", "Alpha", "Beta"])
    }

    func testEssentialsGroupByContainerDefaultFirst() {
        let snapshot = SpacesSnapshot(records: [
            space("{a}", "Alpha", children: []),
            container("builtin-2", "Work"),
            tab("e1", essential: true),
            tab("e2", essential: true),
            tab("e3", essential: true, container: "builtin-2"),
            tab("e4", essential: true),
            layout(spaces: ["{a}"], essentials: ["builtin-2": ["e3"], "default": ["e2", "e1"]]),
        ])
        XCTAssertEqual(snapshot.essentials.map(\.key), ["default", "builtin-2"])
        XCTAssertEqual(snapshot.essentials[0].tabs.map(\.tabId), ["e2", "e1", "e4"])
        XCTAssertEqual(snapshot.essentials[1].container?.name, "Work")
    }

    func testReportsDanglingChildrenAndUnplacedRecords() {
        let snapshot = SpacesSnapshot(records: [
            space("{a}", "Alpha", children: ["gone"]),
            tab("orphan", space: "{a}"),
            layout(spaces: ["{a}"], essentials: [:]),
        ])
        XCTAssertEqual(snapshot.spaces[0].items, [.missing(id: "gone")])
        XCTAssertEqual(snapshot.issues, [
            "Space Alpha lists unknown child gone",
            "1 tab/folder/split records are not listed by any parent",
        ])
    }

    func testSurvivesFolderCycle() {
        let snapshot = SpacesSnapshot(records: [
            space("{a}", "Alpha", children: ["f1"]),
            folder("f1", "One", space: "{a}", children: ["f2"]),
            folder("f2", "Two", space: "{a}", parent: "f1", children: ["f1"]),
            layout(spaces: ["{a}"], essentials: [:]),
        ])
        XCTAssertEqual(outline(snapshot.spaces[0].items), ["folder f1", "  folder f2", "    missing f1"])
        XCTAssertEqual(snapshot.issues, ["Folder cycle through f1"])
    }

    func testCountsTombstonesAndUnknownKinds() {
        let snapshot = SpacesSnapshot(records: [
            SpacesRecord(id: "x", modified: .distantPast, body: .tombstone, raw: nil),
            SpacesRecord(id: "y", modified: .distantPast, body: .unknown(kind: "widget"), raw: nil),
        ])
        XCTAssertEqual(snapshot.tombstoneCount, 1)
        XCTAssertEqual(snapshot.unknownKinds, ["widget": 1])
    }

    // MARK: - Helpers

    private func outline(_ items: [SidebarItem], depth: Int = 0) -> [String] {
        let pad = String(repeating: "  ", count: depth)
        return items.flatMap { item -> [String] in
            switch item {
            case .tab(let tab): return ["\(pad)tab \(tab.tabId)"]
            case .split(let split): return ["\(pad)split \(split.record.splitId) [\(split.tabs.map(\.tabId).joined(separator: ", "))]"]
            case .missing(let id): return ["\(pad)missing \(id)"]
            case .folder(let folder):
                return ["\(pad)folder \(folder.record.folderId)"] + outline(folder.items, depth: depth + 1)
            }
        }
    }

    private func record(_ id: String, _ body: SpacesRecordBody) -> SpacesRecord {
        SpacesRecord(id: id, modified: .distantPast, body: body, raw: nil)
    }

    private func space(_ uuid: String, _ name: String, children: [String]) -> SpacesRecord {
        record(uuid, .space(SpaceRecord(uuid: uuid,
                                        name: name,
                                        icon: nil,
                                        theme: nil,
                                        containerGuid: nil,
                                        children: children)))
    }

    private func folder(_ id: String,
                        _ name: String,
                        space: String,
                        parent: String? = nil,
                        children: [String]) -> SpacesRecord {
        record(id, .folder(FolderRecord(folderId: id,
                                        name: name,
                                        icon: nil,
                                        workspaceUuid: space,
                                        parentFolderId: parent,
                                        live: nil,
                                        children: children)))
    }

    private func tab(_ id: String,
                     space: String? = nil,
                     folder: String? = nil,
                     essential: Bool = false,
                     container: String? = nil) -> SpacesRecord {
        record(id, .tab(TabRecord(tabId: id,
                                  url: "https://\(id).example/",
                                  title: id,
                                  icon: "",
                                  containerGuid: container,
                                  essential: essential,
                                  pinned: true,
                                  workspaceUuid: essential ? nil : space,
                                  folderId: folder,
                                  staticLabel: nil,
                                  hasStaticIcon: false,
                                  defaultContainer: false)))
    }

    private func split(_ id: String, tabs: [String], space: String) -> SpacesRecord {
        record(id, .split(SplitRecord(splitId: id,
                                      gridType: "grid",
                                      pinned: true,
                                      tabs: tabs,
                                      workspaceUuid: space,
                                      folderId: nil)))
    }

    private func container(_ guid: String, _ name: String) -> SpacesRecord {
        record(guid, .container(ContainerRecord(guid: guid, name: name, icon: "briefcase", color: "orange")))
    }

    private func layout(spaces: [String], essentials: [String: [String]]) -> SpacesRecord {
        record("layout", .layout(LayoutRecord(spaces: spaces, essentials: essentials)))
    }
}
