// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Combine
import Foundation

/// The last fetched records on disk, so spaces show instantly and offline.
public struct SpacesCache: Sendable {
    private struct Entry: Codable {
        let id: String
        let modified: Date
        let raw: JSONValue
    }

    private struct File: Codable {
        let version: Int
        let fetchedAt: Date
        let entries: [Entry]
    }

    private static let version = 1

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func save(_ records: [SpacesRecord], fetchedAt: Date) throws {
        let entries = records.compactMap { record in
            record.raw.map { Entry(id: record.id, modified: record.modified, raw: $0) }
        }
        let data = try JSONEncoder().encode(File(version: Self.version, fetchedAt: fetchedAt, entries: entries))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Nil when there is no cache or it was written by an incompatible version.
    public func load() -> (records: [SpacesRecord], fetchedAt: Date)? {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data),
              file.version == Self.version
        else { return nil }
        let records = file.entries.compactMap { entry -> SpacesRecord? in
            guard let cleartext = try? JSONEncoder().encode(entry.raw) else { return nil }
            return SpacesRecord(id: entry.id, modified: entry.modified, cleartext: cleartext)
        }
        return (records, file.fetchedAt)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// A page to pin: where it is, what it is called, and its favicon as a
/// `data:` URL if one could be made.
public struct PinnablePage: Sendable, Equatable {
    public let url: URL
    public let title: String
    public let icon: String?

    public init(url: URL, title: String, icon: String? = nil) {
        self.url = url
        self.title = title
        self.icon = icon
    }
}

/// Holds the current spaces snapshot for the UI: cached first, then
/// refreshed from Sync on demand.
@MainActor
public final class SpacesStore: ObservableObject {
    public enum Status: Equatable {
        case idle
        case refreshing
        case failed(String)
    }

    @Published public private(set) var snapshot: SpacesSnapshot?
    @Published public private(set) var fetchedAt: Date?
    @Published public private(set) var status: Status = .idle
    /// Set when the last fetch failed only because there is no account to
    /// read from, which the UI answers with a way in rather than an error.
    @Published public private(set) var needsSignIn = false

    public typealias Rename = @MainActor (_ target: RenameTarget, _ name: String) async throws -> SpacesRecord
    public typealias Pin = @MainActor (_ page: PinnablePage, _ spaceUUID: String) async throws -> PinnedTab
    public typealias Unpin = @MainActor (_ tabID: String) async throws -> UnpinnedTab
    public typealias CreateSpace = @MainActor (_ name: String) async throws -> CreatedSpace
    public typealias SetIcon = @MainActor (_ spaceUUID: String, _ icon: SpaceIcon) async throws -> SpacesRecord
    public typealias MoveTab = @MainActor (_ tabID: String, _ folderID: String?) async throws -> MovedTab
    public typealias Move = @MainActor (_ itemID: String, _ parent: ReorderParent, _ beforeID: String?)
        async throws -> SpacesRecord

    private let cache: SpacesCache
    private let fetch: @MainActor () async throws -> SpacesFetchResult
    private let rename: Rename
    private let pin: Pin
    private let unpin: Unpin
    private let move: Move
    private let moveTab: MoveTab
    private let setIcon: SetIcon
    private let createSpace: CreateSpace
    /// Moves are sent one at a time, in the order they were made.
    private var lastMove: Task<Void, Never>?
    private var records: [SpacesRecord] = []
    /// Ids this store wrote, kept until a fetch has caught up with them.
    private var writtenLocally: Set<String> = []

    public init(cache: SpacesCache,
                fetch: @escaping @MainActor () async throws -> SpacesFetchResult,
                rename: @escaping Rename,
                pin: @escaping Pin,
                unpin: @escaping Unpin,
                move: @escaping Move,
                moveTab: @escaping MoveTab,
                setIcon: @escaping SetIcon,
                createSpace: @escaping CreateSpace) {
        self.cache = cache
        self.fetch = fetch
        self.rename = rename
        self.pin = pin
        self.unpin = unpin
        self.move = move
        self.moveTab = moveTab
        self.setIcon = setIcon
        self.createSpace = createSpace
        if let cached = cache.load() {
            records = cached.records
            snapshot = SpacesSnapshot(records: cached.records)
            fetchedAt = cached.fetchedAt
        }
    }

    /// Fetches from Sync. A failure keeps the previous snapshot visible.
    public func refresh() async {
        guard status != .refreshing else { return }
        status = .refreshing
        do {
            let result = try await fetch()
            (records, writtenLocally) = Self.merge(local: records,
                                                   fetched: result.records,
                                                   writtenLocally: writtenLocally)
            snapshot = SpacesSnapshot(records: records)
            fetchedAt = result.fetchedAt
            status = .idle
            needsSignIn = false
            try? cache.save(records, fetchedAt: result.fetchedAt)
        } catch is SpacesSignInRequired {
            needsSignIn = true
            status = .idle
        } catch {
            needsSignIn = false
            status = .failed(String(describing: error))
        }
    }

    /// Renames on the server first; the local copy only changes once the
    /// server accepted the write.
    public func rename(_ target: RenameTarget, to name: String) async throws {
        let updated = try await rename(target, name)
        replace(updated)
    }

    /// Pins on the server first; returns the new tab's Zen id.
    @discardableResult
    public func pin(_ page: PinnablePage, toSpace spaceUUID: String) async throws -> TabRecord? {
        let pinned = try await pin(page, spaceUUID)
        replace(pinned.tab)
        replace(pinned.space)
        if case .tab(let tab) = pinned.tab.body { return tab }
        return nil
    }

    /// Unpins on the server first; the tab disappears here once it is gone there.
    public func unpin(tabID: String) async throws {
        let unpinned = try await unpin(tabID)
        replace(unpinned.parent)
        replace(unpinned.tombstone)
    }

    /// Shown once the server has accepted it. Returns the new space's uuid.
    @discardableResult
    public func createSpace(named name: String) async throws -> String {
        let created = try await createSpace(name)
        created.records.forEach(replace)
        return created.space.id
    }

    /// Shown once the server has accepted it.
    public func setIcon(_ icon: SpaceIcon, forSpace uuid: String) async throws {
        replace(try await setIcon(uuid, icon))
    }

    /// Into a folder of the tab's space, or out to its top level when
    /// `folderID` is nil. Shown once the server has accepted it.
    public func moveTab(_ tabID: String, toFolder folderID: String?) async throws {
        let moved = try await moveTab(tabID, folderID)
        moved.records.forEach(replace)
    }

    /// Unlike the other writes this shows at once, so a dragged row stays
    /// where it was dropped; if the server refuses, the parent goes back to
    /// how it was before this move.
    public func move(_ itemID: String, in parent: ReorderParent, before beforeID: String?) async throws {
        guard let index = records.firstIndex(where: { $0.id == parent.id }),
              let raw = records[index].raw,
              case .array(let children)? = raw["data"]?["children"],
              let cleartext = try? JSONEncoder().encode(raw)
        else { throw ZenSpacesWriteError.recordNotFound(parent.id) }
        let previous = records[index]
        let local = try ZenSpacesWriter.changed(cleartext, id: parent.id, kind: parent.kind) { data in
            data["children"] = .array(ZenSpacesWriter.moving(itemID, before: beforeID, in: children))
        }
        replace(SpacesRecord(id: parent.id, modified: Date(), cleartext: local))

        let before = lastMove
        let write = Task { () -> Result<SpacesRecord, Error> in
            await before?.value
            do {
                return .success(try await move(itemID, parent, beforeID))
            } catch {
                return .failure(error)
            }
        }
        lastMove = Task { _ = await write.value }
        switch await write.value {
        case .success(let updated):
            replace(updated)
        case .failure(let error):
            replace(previous)
            throw error
        }
    }

    /// A fetch that started before a local write finished must not undo it:
    /// a locally written record wins while it is newer than the fetched one,
    /// or is missing from the fetch altogether (just created).
    static func merge(local: [SpacesRecord],
                      fetched: [SpacesRecord],
                      writtenLocally: Set<String>) -> (records: [SpacesRecord], writtenLocally: Set<String>) {
        let localByID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let fetchedIDs = Set(fetched.map(\.id))
        var stillPending: Set<String> = []
        var merged = fetched.map { record -> SpacesRecord in
            guard writtenLocally.contains(record.id),
                  let mine = localByID[record.id],
                  mine.modified > record.modified
            else { return record }
            stillPending.insert(record.id)
            return mine
        }
        for id in writtenLocally where !fetchedIDs.contains(id) {
            if let mine = localByID[id] {
                merged.append(mine)
                stillPending.insert(id)
            }
        }
        return (merged, stillPending)
    }

    private func replace(_ record: SpacesRecord) {
        writtenLocally.insert(record.id)
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.append(record)
        }
        snapshot = SpacesSnapshot(records: records)
        try? cache.save(records, fetchedAt: fetchedAt ?? Date())
    }

    /// Forgets everything, e.g. after the account signs out.
    public func reset() {
        records = []
        writtenLocally = []
        cache.clear()
        snapshot = nil
        fetchedAt = nil
        status = .idle
    }
}
