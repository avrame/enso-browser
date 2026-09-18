// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

// Zen's `spaces` collection records. Field names, defaults and meanings
// follow zen-browser/desktop src/zen/sync/ZenSpacesSyncModel.sys.mjs;
// see SPACES-SYNC-FORMAT.md in the zen-mobile workspace.

public struct ContainerRecord: Sendable, Equatable {
    public let guid: String
    public let name: String
    public let icon: String
    public let color: String
}

public struct SpaceRecord: Sendable, Equatable {
    public let uuid: String
    public let name: String
    public let icon: String?
    public let theme: JSONValue?
    public let containerGuid: String?
    public let children: [String]
}

public struct FolderRecord: Sendable, Equatable {
    public struct Live: Sendable, Equatable {
        public let type: String
        public let state: JSONValue?
    }

    public let folderId: String
    public let name: String
    public let icon: String?
    public let workspaceUuid: String?
    public let parentFolderId: String?
    public let live: Live?
    public let children: [String]
}

public struct TabRecord: Sendable, Equatable {
    public let tabId: String
    public let url: String
    public let title: String
    public let icon: String
    public let containerGuid: String?
    public let essential: Bool
    public let pinned: Bool
    public let workspaceUuid: String?
    public let folderId: String?
    public let staticLabel: String?
    public let hasStaticIcon: Bool
    public let defaultContainer: Bool

    /// What the sidebar shows: a user-set label wins over the page title.
    public var displayTitle: String {
        if let staticLabel, !staticLabel.isEmpty { return staticLabel }
        return title.isEmpty ? url : title
    }
}

public struct SplitRecord: Sendable, Equatable {
    public let splitId: String
    public let gridType: String
    public let pinned: Bool
    public let tabs: [String]
    public let workspaceUuid: String?
    public let folderId: String?
}

public struct LayoutRecord: Sendable, Equatable {
    public let spaces: [String]
    /// Keyed by container guid, or `"default"` for no container.
    public let essentials: [String: [String]]
}

public enum SpacesRecordBody: Sendable, Equatable {
    case container(ContainerRecord)
    case space(SpaceRecord)
    case folder(FolderRecord)
    case tab(TabRecord)
    case split(SplitRecord)
    case layout(LayoutRecord)
    case tombstone
    /// A kind this client does not know (a newer Zen). Must never be
    /// written back or tombstoned.
    case unknown(kind: String)
    case malformed(reason: String)
}

public struct SpacesRecord: Sendable, Equatable {
    public let id: String
    public let modified: Date
    public let body: SpacesRecordBody
    /// The decrypted cleartext as received, kept for round-tripping.
    public let raw: JSONValue?

    public init(id: String, modified: Date, body: SpacesRecordBody, raw: JSONValue?) {
        self.id = id
        self.modified = modified
        self.body = body
        self.raw = raw
    }

    public init(id: String, modified: Date, cleartext: Data) {
        let raw: JSONValue
        do {
            raw = try JSONDecoder().decode(JSONValue.self, from: cleartext)
        } catch {
            self.init(id: id, modified: modified, body: .malformed(reason: "not JSON"), raw: nil)
            return
        }
        self.init(id: id, modified: modified, body: Self.body(of: raw), raw: raw)
    }

    private static func body(of raw: JSONValue) -> SpacesRecordBody {
        if raw["deleted"]?.boolValue == true { return .tombstone }
        guard let kind = raw["kind"]?.stringValue else { return .malformed(reason: "no kind") }
        guard let data = raw["data"], case .object = data else { return .malformed(reason: "no data for \(kind)") }
        let fields = Fields(data)
        do {
            switch kind {
            case "container":
                return .container(ContainerRecord(guid: try fields.string("guid"),
                                                  name: fields.string("name", default: ""),
                                                  icon: fields.string("icon", default: ""),
                                                  color: fields.string("color", default: "")))
            case "space":
                return .space(SpaceRecord(uuid: try fields.string("uuid"),
                                          name: fields.string("name", default: ""),
                                          icon: fields.optionalString("icon"),
                                          theme: fields.value("theme"),
                                          containerGuid: fields.optionalString("containerGuid"),
                                          children: fields.strings("children")))
            case "folder":
                return .folder(FolderRecord(folderId: try fields.string("folderId"),
                                            name: fields.string("name", default: ""),
                                            icon: fields.optionalString("icon"),
                                            workspaceUuid: fields.optionalString("workspaceUuid"),
                                            parentFolderId: fields.optionalString("parentFolderId"),
                                            live: fields.live("live"),
                                            children: fields.strings("children")))
            case "tab":
                return .tab(TabRecord(tabId: try fields.string("tabId"),
                                      url: try fields.string("url"),
                                      title: fields.string("title", default: ""),
                                      icon: fields.string("icon", default: ""),
                                      containerGuid: fields.optionalString("containerGuid"),
                                      essential: fields.bool("essential"),
                                      pinned: fields.bool("pinned", default: true),
                                      workspaceUuid: fields.optionalString("workspaceUuid"),
                                      folderId: fields.optionalString("folderId"),
                                      staticLabel: fields.optionalString("staticLabel"),
                                      hasStaticIcon: fields.bool("hasStaticIcon"),
                                      defaultContainer: fields.bool("defaultContainer")))
            case "split":
                return .split(SplitRecord(splitId: try fields.string("splitId"),
                                          gridType: fields.string("gridType", default: "grid"),
                                          pinned: fields.bool("pinned", default: true),
                                          tabs: fields.strings("tabs"),
                                          workspaceUuid: fields.optionalString("workspaceUuid"),
                                          folderId: fields.optionalString("folderId")))
            case "layout":
                return .layout(LayoutRecord(spaces: fields.strings("spaces"),
                                            essentials: fields.stringLists("essentials")))
            default:
                return .unknown(kind: kind)
            }
        } catch let MissingField.field(name) {
            return .malformed(reason: "\(kind) without \(name)")
        } catch {
            return .malformed(reason: "\(kind): \(error)")
        }
    }
}

private enum MissingField: Error {
    case field(String)
}

/// Lenient field access: absent or `null` optional fields read as their
/// defaults, so an added or dropped Zen field does not reject a record.
private struct Fields {
    let data: JSONValue

    init(_ data: JSONValue) {
        self.data = data
    }

    func value(_ key: String) -> JSONValue? {
        guard let value = data[key], value != .null else { return nil }
        return value
    }

    func string(_ key: String) throws -> String {
        guard let string = value(key)?.stringValue, !string.isEmpty else { throw MissingField.field(key) }
        return string
    }

    func string(_ key: String, default fallback: String) -> String {
        value(key)?.stringValue ?? fallback
    }

    func optionalString(_ key: String) -> String? {
        guard let string = value(key)?.stringValue, !string.isEmpty else { return nil }
        return string
    }

    func bool(_ key: String, default fallback: Bool = false) -> Bool {
        value(key)?.boolValue ?? fallback
    }

    func strings(_ key: String) -> [String] {
        guard case .array(let items)? = value(key) else { return [] }
        return items.compactMap(\.stringValue)
    }

    func stringLists(_ key: String) -> [String: [String]] {
        guard case .object(let object)? = value(key) else { return [:] }
        return object.mapValues { list in
            guard case .array(let items) = list else { return [] }
            return items.compactMap(\.stringValue)
        }
    }

    func live(_ key: String) -> FolderRecord.Live? {
        guard let live = value(key), let type = live["type"]?.stringValue else { return nil }
        return FolderRecord.Live(type: type, state: live["state"])
    }
}
