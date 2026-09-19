// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Account
import ZenSpacesKit

/// The app-wide spaces store, shared by every window.
@MainActor
enum ZenSpacesService {
    static let store = makeStore()
    static let pinnedTabLinks = PinnedTabLinks()

    private static let directory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ZenSpaces")

    private static func makeStore() -> SpacesStore {
        #if MOZ_CHANNEL_developer
        // Launch with ZEN_SPACES_DEMO=<count> to show generated spaces instead of the account's.
        if let count = ProcessInfo.processInfo.environment["ZEN_SPACES_DEMO"].flatMap(Int.init), count > 0 {
            let demo = DemoSpaces(records: SpacesDemoData.records(spaceCount: count))
            return SpacesStore(cache: SpacesCache(url: directory.appendingPathComponent("demo.json")),
                               fetch: demo.fetch,
                               rename: demo.rename,
                               pin: demo.pin,
                               unpin: demo.unpin,
                               move: demo.move,
                               moveTab: demo.moveTab,
                               setIcon: demo.setIcon,
                               createSpace: demo.createSpace)
        }
        #endif
        return SpacesStore(cache: SpacesCache(url: directory.appendingPathComponent("spaces.json")),
                           fetch: fetch,
                           rename: rename,
                           pin: pin,
                           unpin: unpin,
                           move: move,
                           moveTab: moveTab,
                           setIcon: setIcon,
                           createSpace: createSpace)
    }

    private static func fetch() async throws -> SpacesFetchResult {
        try await ZenSpacesReader(auth: auth()).fetch()
    }

    private static func rename(_ target: RenameTarget, _ name: String) async throws -> SpacesRecord {
        try await ZenSpacesWriter(auth: auth()).rename(target, to: name)
    }

    private static func pin(_ page: PinnablePage, _ spaceUUID: String) async throws -> PinnedTab {
        try await ZenSpacesWriter(auth: auth()).pinTab(url: page.url, title: page.title, icon: page.icon, inSpace: spaceUUID)
    }

    private static func unpin(_ tabID: String) async throws -> UnpinnedTab {
        try await ZenSpacesWriter(auth: auth()).unpinTab(tabID)
    }

    private static func move(_ itemID: String, _ parent: ReorderParent, _ beforeID: String?) async throws -> SpacesRecord {
        try await ZenSpacesWriter(auth: auth()).move(itemID, in: parent, before: beforeID)
    }

    private static func moveTab(_ tabID: String, _ folderID: String?) async throws -> MovedTab {
        try await ZenSpacesWriter(auth: auth()).moveTab(tabID, toFolder: folderID)
    }

    private static func setIcon(_ uuid: String, _ icon: SpaceIcon) async throws -> SpacesRecord {
        try await ZenSpacesWriter(auth: auth()).setSpaceIcon(uuid, to: icon)
    }

    private static func createSpace(_ name: String) async throws -> CreatedSpace {
        try await ZenSpacesWriter(auth: auth()).createSpace(named: name)
    }

    private static func auth() async throws -> SyncAuth {
        try await ZenSpacesAuthProvider(accountManager: RustFirefoxAccounts.shared.accountManager).auth()
    }
}

/// In-memory stand-in for the server in demo mode.
@MainActor
private final class DemoSpaces {
    private var records: [SpacesRecord]

    init(records: [SpacesRecord]) {
        self.records = records
    }

    func fetch() async throws -> SpacesFetchResult {
        SpacesFetchResult(records: records,
                          snapshot: SpacesSnapshot(records: records),
                          engineVersion: ZenSpacesReader.supportedEngineVersion,
                          fetchedAt: Date())
    }

    func rename(_ target: RenameTarget, _ name: String) async throws -> SpacesRecord {
        try await Task.sleep(for: .seconds(1))
        let name = try ZenSpacesWriter.validName(name)
        guard let index = records.firstIndex(where: { $0.id == target.id }),
              let raw = records[index].raw,
              let cleartext = try? JSONEncoder().encode(raw)
        else { throw ZenSpacesWriteError.recordNotFound(target.id) }
        let changed = try ZenSpacesWriter.changed(cleartext, id: target.id, kind: target.kind) {
            $0["name"] = .string(name)
        }
        let record = SpacesRecord(id: target.id, modified: Date(), cleartext: changed)
        records[index] = record
        return record
    }

    func pin(_ page: PinnablePage, _ spaceUUID: String) async throws -> PinnedTab {
        try await Task.sleep(for: .seconds(1))
        guard let index = records.firstIndex(where: { $0.id == spaceUUID }),
              let raw = records[index].raw,
              let spaceCleartext = try? JSONEncoder().encode(raw)
        else { throw ZenSpacesWriteError.recordNotFound(spaceUUID) }
        let tabID = ZenSpacesWriter.newTabSyncID()
        let tabCleartext = try ZenSpacesWriter.newPinnedTab(id: tabID,
                                                            url: page.url,
                                                            title: page.title,
                                                            icon: page.icon,
                                                            spaceUUID: spaceUUID,
                                                            containerGuid: raw["data"]?["containerGuid"]?.stringValue)
        let changedSpace = try ZenSpacesWriter.changed(spaceCleartext, id: spaceUUID, kind: "space") { data in
            guard case .array(let children)? = data["children"] else { return }
            data["children"] = .array(children + [.string(tabID)])
        }
        let tab = SpacesRecord(id: tabID, modified: Date(), cleartext: tabCleartext)
        let space = SpacesRecord(id: spaceUUID, modified: Date(), cleartext: changedSpace)
        records.append(tab)
        records[index] = space
        return PinnedTab(tab: tab, space: space)
    }

    func move(_ itemID: String, _ parent: ReorderParent, _ beforeID: String?) async throws -> SpacesRecord {
        try await Task.sleep(for: .seconds(1))
        guard let index = records.firstIndex(where: { $0.id == parent.id }),
              let raw = records[index].raw,
              let cleartext = try? JSONEncoder().encode(raw)
        else { throw ZenSpacesWriteError.recordNotFound(parent.id) }
        let changed = try ZenSpacesWriter.changed(cleartext, id: parent.id, kind: parent.kind) { data in
            guard case .array(let children)? = data["children"] else { return }
            data["children"] = .array(ZenSpacesWriter.moving(itemID, before: beforeID, in: children))
        }
        let record = SpacesRecord(id: parent.id, modified: Date(), cleartext: changed)
        records[index] = record
        return record
    }

    func createSpace(_ name: String) async throws -> CreatedSpace {
        try await Task.sleep(for: .seconds(1))
        let uuid = ZenSpacesWriter.newSpaceUUID()
        let space = SpacesRecord(id: uuid,
                                 modified: Date(),
                                 cleartext: try ZenSpacesWriter.newSpace(uuid: uuid,
                                                                         name: try ZenSpacesWriter.validName(name),
                                                                         icon: nil))
        records.append(space)
        let layout = try edit(LayoutRecord.id, kind: "layout") { data in
            guard case .array(let spaces)? = data["spaces"] else { return }
            data["spaces"] = .array(spaces + [.string(uuid)])
        }
        return CreatedSpace(space: space, layout: layout)
    }

    func setIcon(_ uuid: String, _ icon: SpaceIcon) async throws -> SpacesRecord {
        try await Task.sleep(for: .seconds(1))
        let stored = try ZenSpacesWriter.validIcon(icon)
        return try edit(uuid, kind: "space") { $0["icon"] = stored.map(JSONValue.string) ?? .null }
    }

    func moveTab(_ tabID: String, _ folderID: String?) async throws -> MovedTab {
        try await Task.sleep(for: .seconds(1))
        guard let tabIndex = records.firstIndex(where: { $0.id == tabID }),
              case .tab(let tab) = records[tabIndex].body,
              let spaceID = tab.workspaceUuid
        else { throw ZenSpacesWriteError.recordNotFound(tabID) }
        let source = tab.folderId ?? spaceID
        let destination = folderID ?? spaceID
        let movedTab = try edit(tabID, kind: "tab") { $0["folderId"] = folderID.map(JSONValue.string) ?? .null }
        let added = try edit(destination, kind: folderID == nil ? "space" : "folder") { data in
            guard case .array(let children)? = data["children"] else { return }
            data["children"] = .array(children + [.string(tabID)])
        }
        let removed = try edit(source, kind: tab.folderId == nil ? "space" : "folder") { data in
            guard case .array(let children)? = data["children"] else { return }
            data["children"] = .array(children.filter { $0 != .string(tabID) })
        }
        return MovedTab(tab: movedTab, destination: added, source: removed)
    }

    private func edit(_ id: String, kind: String, change: (inout [String: JSONValue]) -> Void) throws -> SpacesRecord {
        guard let index = records.firstIndex(where: { $0.id == id }),
              let raw = records[index].raw,
              let cleartext = try? JSONEncoder().encode(raw)
        else { throw ZenSpacesWriteError.recordNotFound(id) }
        let record = SpacesRecord(id: id,
                                  modified: Date(),
                                  cleartext: try ZenSpacesWriter.changed(cleartext, id: id, kind: kind, change: change))
        records[index] = record
        return record
    }

    func unpin(_ tabID: String) async throws -> UnpinnedTab {
        try await Task.sleep(for: .seconds(1))
        guard let tabIndex = records.firstIndex(where: { $0.id == tabID }),
              case .tab(let tab) = records[tabIndex].body,
              let parentID = tab.folderId ?? tab.workspaceUuid,
              let parentIndex = records.firstIndex(where: { $0.id == parentID }),
              let raw = records[parentIndex].raw,
              let cleartext = try? JSONEncoder().encode(raw)
        else { throw ZenSpacesWriteError.recordNotFound(tabID) }
        let kind = tab.folderId == nil ? "space" : "folder"
        let changed = try ZenSpacesWriter.changed(cleartext, id: parentID, kind: kind) { data in
            guard case .array(let children)? = data["children"] else { return }
            data["children"] = .array(children.filter { $0 != .string(tabID) })
        }
        let parent = SpacesRecord(id: parentID, modified: Date(), cleartext: changed)
        let tombstone = SpacesRecord(id: tabID,
                                     modified: Date(),
                                     cleartext: Data(#"{"id":"\#(tabID)","deleted":true}"#.utf8))
        records[parentIndex] = parent
        records[tabIndex] = tombstone
        return UnpinnedTab(parent: parent, tombstone: tombstone)
    }
}
