// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

/// Something the user can rename, identified by its record id.
public enum RenameTarget: Sendable, Equatable {
    case space(String)
    case folder(String)

    public var id: String {
        switch self {
        case .space(let id), .folder(let id): return id
        }
    }

    /// The record `kind` Zen uses for it.
    public var kind: String {
        switch self {
        case .space: return "space"
        case .folder: return "folder"
        }
    }
}

/// The records a pin wrote: the new tab and its space's updated `children`.
public struct PinnedTab: Sendable {
    public let tab: SpacesRecord
    public let space: SpacesRecord

    public init(tab: SpacesRecord, space: SpacesRecord) {
        self.tab = tab
        self.space = space
    }
}

/// The records an unpin wrote: the tab's parent without it, and the tab's tombstone.
public struct UnpinnedTab: Sendable {
    public let parent: SpacesRecord
    public let tombstone: SpacesRecord

    public init(parent: SpacesRecord, tombstone: SpacesRecord) {
        self.parent = parent
        self.tombstone = tombstone
    }
}

public enum ZenSpacesWriteError: Error, Equatable, CustomStringConvertible {
    /// Writes are only safe against the exact format this client knows.
    case unsupportedEngineVersion(Int?)
    case recordNotFound(String)
    case unexpectedRecord(id: String, reason: String)
    case invalidName
    /// Only web pages can be pinned.
    case unpinnableURL(String)
    /// A generated tab id already exists on the server (should never happen).
    case idCollision(String)
    /// The record kept changing under us; the edit was not applied.
    case conflict(String)

    public var description: String {
        switch self {
        case .unsupportedEngineVersion(let version):
            let found = version.map(String.init) ?? "none"
            return "Zen's spaces format on the server is version \(found); this app only writes version "
                + "\(ZenSpacesReader.supportedEngineVersion)."
        case .recordNotFound: return "That item is no longer on the server. Pull to refresh."
        case .unexpectedRecord(_, let reason): return "The server copy looks different than expected: \(reason)"
        case .invalidName: return "The name can't be empty."
        case .unpinnableURL: return "Only web pages (http or https) can be pinned."
        case .idCollision: return "Couldn't create the pinned tab. Try again."
        case .conflict: return "It kept changing on another device. Try again."
        }
    }
}

/// Changes Zen records on the server one field at a time. Every write
/// re-reads the server copy, changes only the named field, keeps every
/// other field as received (including ones this client does not model),
/// and is conditional on that copy being unchanged. The only deletion is
/// `unpinTab`, which removes one pinned tab after checks.
public struct ZenSpacesWriter: Sendable {
    private let client: SyncStorageClient
    private let maxAttempts = 3
    private let makeTabID: @Sendable () -> String

    public init(auth: SyncAuth,
                transport: HTTPTransport = URLSessionTransport(),
                makeTabID: @escaping @Sendable () -> String = ZenSpacesWriter.newTabSyncID) {
        self.client = SyncStorageClient(auth: auth, transport: transport)
        self.makeTabID = makeTabID
    }

    /// Zen's own form (ZenWindowSync.#newTabSyncId): `<ms since 1970>-<lowercase uuid>`.
    public static func newTabSyncID() -> String {
        "\(Int64(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.lowercased())"
    }

    /// Pins a page at the end of a space's pinned tabs. The tab record is
    /// created first and only then listed in the space's `children`: if the
    /// second write fails, Zen still places the tab by its `workspaceUuid`
    /// and repairs the order on its next upload, whereas the reverse order
    /// could leave the space naming a tab that does not exist.
    /// `icon` is kept only as a `data:` URL, the only form Zen accepts.
    public func pinTab(url: URL, title: String, icon: String? = nil, inSpace spaceUUID: String) async throws -> PinnedTab {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw ZenSpacesWriteError.unpinnableURL(url.absoluteString)
        }
        try await checkEngineVersion()

        let space: (bso: BSO, cleartext: Data)
        do {
            space = try await client.record(id: spaceUUID, in: ZenSpacesReader.collection)
        } catch SyncStorageError.notFound {
            throw ZenSpacesWriteError.recordNotFound(spaceUUID)
        }
        let spaceRaw = try JSONDecoder().decode(JSONValue.self, from: space.cleartext)
        guard spaceRaw["kind"]?.stringValue == "space", spaceRaw["deleted"]?.boolValue != true else {
            throw ZenSpacesWriteError.unexpectedRecord(id: spaceUUID, reason: "not a space")
        }
        let containerGuid = spaceRaw["data"]?["containerGuid"]?.stringValue

        let tabID = makeTabID()
        let tabCleartext = try Self.newPinnedTab(id: tabID,
                                                 url: url,
                                                 title: title,
                                                 icon: icon,
                                                 spaceUUID: spaceUUID,
                                                 containerGuid: containerGuid)
        let tabModified: Double
        do {
            tabModified = try await client.put(id: tabID,
                                               in: ZenSpacesReader.collection,
                                               cleartext: tabCleartext,
                                               ifUnmodifiedSince: 0)
        } catch SyncStorageError.modifiedSince {
            throw ZenSpacesWriteError.idCollision(tabID)
        }
        let tab = SpacesRecord(id: tabID, modified: Date(timeIntervalSince1970: tabModified), cleartext: tabCleartext)

        let updatedSpace = try await updateRecord(id: spaceUUID, kind: "space") { data in
            guard case .array(var children)? = data["children"] else {
                data["children"] = .array([.string(tabID)])
                return
            }
            if !children.contains(.string(tabID)) {
                children.append(.string(tabID))
            }
            data["children"] = .array(children)
        }
        return PinnedTab(tab: tab, space: updatedSpace)
    }

    /// A pinned tab record as Zen's model projects one (ZenSpacesSyncModel
    /// #projectTabs). A space with a container opens its tabs in it.
    public static func newPinnedTab(id: String,
                                    url: URL,
                                    title: String,
                                    icon: String? = nil,
                                    spaceUUID: String,
                                    containerGuid: String?) throws -> Data {
        let container: JSONValue = containerGuid.map(JSONValue.string) ?? .null
        let data: [String: JSONValue] = [
            "tabId": .string(id),
            "url": .string(url.absoluteString),
            "title": .string(title),
            "icon": .string(icon.flatMap { $0.hasPrefix("data:") ? $0 : nil } ?? ""),
            "containerGuid": container,
            "essential": .bool(false),
            "pinned": .bool(true),
            "workspaceUuid": .string(spaceUUID),
            "folderId": .null,
            "staticLabel": .null,
            "hasStaticIcon": .bool(false),
            "defaultContainer": .bool(containerGuid != nil),
        ]
        let record: JSONValue = .object(["id": .string(id), "kind": .string("tab"), "data": .object(data)])
        return try JSONEncoder().encode(record)
    }

    /// Removes a pinned tab from its space or folder. Zen closes the tab on
    /// every desktop, as when the tab is closed there. Essentials and tabs in a
    /// split view are refused, as is a tab its parent does not list.
    ///
    /// The parent's `children` changes first and the tombstone goes last: if
    /// the tombstone fails, the tab record still names its space, so Zen keeps
    /// the tab and re-lists it on its next upload. Nothing is lost.
    public func unpinTab(_ tabID: String) async throws -> UnpinnedTab {
        try await checkEngineVersion()

        let tab = try await pinnedTab(tabID)
        let parentKind = tab.folderID == nil ? "space" : "folder"
        guard let parentID = tab.folderID ?? tab.spaceID else {
            throw ZenSpacesWriteError.unexpectedRecord(id: tabID, reason: "not in a space")
        }
        let parent: (bso: BSO, cleartext: Data)
        do {
            parent = try await client.record(id: parentID, in: ZenSpacesReader.collection)
        } catch SyncStorageError.notFound {
            throw ZenSpacesWriteError.recordNotFound(parentID)
        }
        let parentRaw = try JSONDecoder().decode(JSONValue.self, from: parent.cleartext)
        guard case .array(let children)? = parentRaw["data"]?["children"], children.contains(.string(tabID)) else {
            let reason = "not listed in its \(parentKind); it may be in a split view"
            throw ZenSpacesWriteError.unexpectedRecord(id: tabID, reason: reason)
        }

        let updatedParent = try await updateRecord(id: parentID, kind: parentKind) { data in
            guard case .array(let children)? = data["children"] else { return }
            data["children"] = .array(children.filter { $0 != .string(tabID) })
        }
        return UnpinnedTab(parent: updatedParent, tombstone: try await writeTombstone(tabID))
    }

    private struct PinnedTabInfo {
        let bso: BSO
        let spaceID: String?
        let folderID: String?
    }

    /// Reads a tab and checks it is one `unpinTab` may remove.
    private func pinnedTab(_ tabID: String) async throws -> PinnedTabInfo {
        let current: (bso: BSO, cleartext: Data)
        do {
            current = try await client.record(id: tabID, in: ZenSpacesReader.collection)
        } catch SyncStorageError.notFound {
            throw ZenSpacesWriteError.recordNotFound(tabID)
        }
        let raw = try JSONDecoder().decode(JSONValue.self, from: current.cleartext)
        guard raw["deleted"]?.boolValue != true else { throw ZenSpacesWriteError.recordNotFound(tabID) }
        guard raw["kind"]?.stringValue == "tab", let data = raw["data"] else {
            throw ZenSpacesWriteError.unexpectedRecord(id: tabID, reason: "not a tab")
        }
        guard data["essential"]?.boolValue != true else {
            throw ZenSpacesWriteError.unexpectedRecord(id: tabID, reason: "an Essential")
        }
        guard data["pinned"]?.boolValue != false else {
            throw ZenSpacesWriteError.unexpectedRecord(id: tabID, reason: "not pinned")
        }
        return PinnedTabInfo(bso: current.bso,
                             spaceID: data["workspaceUuid"]?.stringValue,
                             folderID: data["folderId"]?.stringValue)
    }

    /// Conditional on the tab being unchanged since it was read; a tab that
    /// is already gone counts as done.
    private func writeTombstone(_ tabID: String) async throws -> SpacesRecord {
        let tombstone = try JSONEncoder().encode(JSONValue.object(["id": .string(tabID), "deleted": .bool(true)]))
        for _ in 0..<maxAttempts {
            let tab: PinnedTabInfo
            do {
                tab = try await pinnedTab(tabID)
            } catch ZenSpacesWriteError.recordNotFound {
                return SpacesRecord(id: tabID, modified: Date(), cleartext: tombstone)
            }
            do {
                let modified = try await client.put(id: tabID,
                                                    in: ZenSpacesReader.collection,
                                                    cleartext: tombstone,
                                                    ifUnmodifiedSince: tab.bso.modified)
                return SpacesRecord(id: tabID, modified: Date(timeIntervalSince1970: modified), cleartext: tombstone)
            } catch SyncStorageError.modifiedSince {
                continue
            }
        }
        throw ZenSpacesWriteError.conflict(tabID)
    }

    /// Spaces and folders both keep their name in `data.name`.
    public func rename(_ target: RenameTarget, to name: String) async throws -> SpacesRecord {
        let name = try Self.validName(name)
        try await checkEngineVersion()
        return try await updateRecord(id: target.id, kind: target.kind) { data in
            data["name"] = .string(name)
        }
    }

    public static func validName(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ZenSpacesWriteError.invalidName }
        return name
    }

    private func checkEngineVersion() async throws {
        let meta = try await client.metaGlobal()
        let version = meta.engines[ZenSpacesReader.collection]?.version
        guard version == ZenSpacesReader.supportedEngineVersion else {
            throw ZenSpacesWriteError.unsupportedEngineVersion(version)
        }
    }

    private func updateRecord(id: String,
                              kind: String,
                              change: @Sendable (inout [String: JSONValue]) -> Void) async throws -> SpacesRecord {
        for _ in 0..<maxAttempts {
            let current: (bso: BSO, cleartext: Data)
            do {
                current = try await client.record(id: id, in: ZenSpacesReader.collection)
            } catch SyncStorageError.notFound {
                throw ZenSpacesWriteError.recordNotFound(id)
            }

            let cleartext = try Self.changed(current.cleartext, id: id, kind: kind, change: change)
            do {
                let modified = try await client.put(id: id,
                                                    in: ZenSpacesReader.collection,
                                                    cleartext: cleartext,
                                                    ifUnmodifiedSince: current.bso.modified)
                return SpacesRecord(id: id, modified: Date(timeIntervalSince1970: modified), cleartext: cleartext)
            } catch SyncStorageError.modifiedSince {
                continue
            }
        }
        throw ZenSpacesWriteError.conflict(id)
    }

    /// Applies `change` to the record's `data`, leaving everything else as is.
    public static func changed(_ cleartext: Data,
                               id: String,
                               kind: String,
                               change: (inout [String: JSONValue]) -> Void) throws -> Data {
        let raw = try JSONDecoder().decode(JSONValue.self, from: cleartext)
        guard case .object(var record) = raw else {
            throw ZenSpacesWriteError.unexpectedRecord(id: id, reason: "not an object")
        }
        guard record["deleted"]?.boolValue != true else {
            throw ZenSpacesWriteError.recordNotFound(id)
        }
        guard record["id"]?.stringValue == id else {
            throw ZenSpacesWriteError.unexpectedRecord(id: id, reason: "id does not match")
        }
        guard record["kind"]?.stringValue == kind else {
            throw ZenSpacesWriteError.unexpectedRecord(id: id, reason: "not a \(kind)")
        }
        guard case .object(var data)? = record["data"] else {
            throw ZenSpacesWriteError.unexpectedRecord(id: id, reason: "no data")
        }
        change(&data)
        record["data"] = .object(data)
        return try JSONEncoder().encode(JSONValue.object(record))
    }
}
