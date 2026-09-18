// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

public indirect enum SidebarItem: Sendable, Equatable {
    case tab(TabRecord)
    case folder(FolderNode)
    case split(SplitNode)
    /// A child id no record in the collection answers to.
    case missing(id: String)
}

public struct FolderNode: Sendable, Equatable {
    public let record: FolderRecord
    public let items: [SidebarItem]
}

public struct SplitNode: Sendable, Equatable {
    public let record: SplitRecord
    public let tabs: [TabRecord]
}

public struct SpaceNode: Sendable, Equatable {
    public let record: SpaceRecord
    public let container: ContainerRecord?
    public let items: [SidebarItem]
}

public struct EssentialsRow: Sendable, Equatable {
    /// A container guid, or `"default"`.
    public let key: String
    public let container: ContainerRecord?
    public let tabs: [TabRecord]
}

/// The sidebar as Zen would lay it out, assembled from the flat records.
/// Ordering lives in the parents: `layout` orders spaces and Essentials,
/// each space's and folder's `children` order their contents.
public struct SpacesSnapshot: Sendable, Equatable {
    public let spaces: [SpaceNode]
    public let essentials: [EssentialsRow]
    public let containers: [String: ContainerRecord]
    public let tombstoneCount: Int
    public let unknownKinds: [String: Int]
    /// Inconsistencies worth seeing while this client is read-only.
    public let issues: [String]

    public init(records: [SpacesRecord]) {
        var containers: [String: ContainerRecord] = [:]
        var spaces: [String: SpaceRecord] = [:]
        var folders: [String: FolderRecord] = [:]
        var tabs: [String: TabRecord] = [:]
        var splits: [String: SplitRecord] = [:]
        var layout: LayoutRecord?
        var tombstones = 0
        var unknownKinds: [String: Int] = [:]
        var issues: [String] = []

        for record in records {
            switch record.body {
            case .container(let container): containers[record.id] = container
            case .space(let space): spaces[record.id] = space
            case .folder(let folder): folders[record.id] = folder
            case .tab(let tab): tabs[record.id] = tab
            case .split(let split): splits[record.id] = split
            case .layout(let value): layout = value
            case .tombstone: tombstones += 1
            case .unknown(let kind): unknownKinds[kind, default: 0] += 1
            case .malformed(let reason): issues.append("Record \(record.id): \(reason)")
            }
        }

        var placed = Set<String>()
        var visitingFolders = Set<String>()

        func resolve(_ ids: [String], in parent: String) -> [SidebarItem] {
            ids.map { id in
                if let tab = tabs[id] {
                    placed.insert(id)
                    return .tab(tab)
                }
                if let split = splits[id] {
                    placed.insert(id)
                    let members = split.tabs.compactMap { tabId -> TabRecord? in
                        guard let tab = tabs[tabId] else {
                            issues.append("Split \(id) names missing tab \(tabId)")
                            return nil
                        }
                        placed.insert(tabId)
                        return tab
                    }
                    return .split(SplitNode(record: split, tabs: members))
                }
                if let folder = folders[id] {
                    guard visitingFolders.insert(id).inserted else {
                        issues.append("Folder cycle through \(id)")
                        return .missing(id: id)
                    }
                    defer { visitingFolders.remove(id) }
                    placed.insert(id)
                    return .folder(FolderNode(record: folder, items: resolve(folder.children, in: id)))
                }
                issues.append("\(parent) lists unknown child \(id)")
                return .missing(id: id)
            }
        }

        var spaceOrder = (layout?.spaces ?? []).filter { spaces[$0] != nil }
        let unlisted = spaces.keys.filter { !spaceOrder.contains($0) }
            .sorted { (spaces[$0]?.name ?? "") < (spaces[$1]?.name ?? "") }
        spaceOrder += unlisted
        if layout == nil, !spaces.isEmpty {
            issues.append("No layout record; spaces are in name order")
        }

        self.spaces = spaceOrder.compactMap { uuid in
            guard let space = spaces[uuid] else { return nil }
            return SpaceNode(record: space,
                             container: space.containerGuid.flatMap { containers[$0] },
                             items: resolve(space.children, in: "Space \(space.name)"))
        }

        var essentialOrder = layout?.essentials ?? [:]
        for tab in tabs.values.sorted(by: { $0.tabId < $1.tabId }) where tab.essential {
            let key = tab.containerGuid ?? "default"
            if !(essentialOrder[key]?.contains(tab.tabId) ?? false) {
                essentialOrder[key, default: []].append(tab.tabId)
            }
        }
        let essentialKeys = essentialOrder.keys.sorted { lhs, rhs in
            if lhs == "default" { return rhs != "default" }
            if rhs == "default" { return false }
            return lhs < rhs
        }
        self.essentials = essentialKeys.compactMap { key in
            let rowTabs = (essentialOrder[key] ?? []).compactMap { id -> TabRecord? in
                placed.insert(id)
                return tabs[id]
            }
            guard !rowTabs.isEmpty else { return nil }
            return EssentialsRow(key: key, container: containers[key], tabs: rowTabs)
        }

        let unplaced = tabs.keys.filter { !placed.contains($0) }.count
            + folders.keys.filter { !placed.contains($0) }.count
            + splits.keys.filter { !placed.contains($0) }.count
        if unplaced > 0 {
            issues.append("\(unplaced) tab/folder/split records are not listed by any parent")
        }

        self.containers = containers
        self.tombstoneCount = tombstones
        self.unknownKinds = unknownKinds
        self.issues = issues
    }
}
