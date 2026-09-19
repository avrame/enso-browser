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

    public typealias Rename = @MainActor (_ target: RenameTarget, _ name: String) async throws -> SpacesRecord
    public typealias Pin = @MainActor (_ url: URL, _ title: String, _ spaceUUID: String) async throws -> PinnedTab

    private let cache: SpacesCache
    private let fetch: @MainActor () async throws -> SpacesFetchResult
    private let rename: Rename
    private let pin: Pin
    private var records: [SpacesRecord] = []
    /// Ids this store wrote, kept until a fetch has caught up with them.
    private var writtenLocally: Set<String> = []

    public init(cache: SpacesCache,
                fetch: @escaping @MainActor () async throws -> SpacesFetchResult,
                rename: @escaping Rename,
                pin: @escaping Pin) {
        self.cache = cache
        self.fetch = fetch
        self.rename = rename
        self.pin = pin
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
            try? cache.save(records, fetchedAt: result.fetchedAt)
        } catch {
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
    public func pin(url: URL, title: String, toSpace spaceUUID: String) async throws -> TabRecord? {
        let pinned = try await pin(url, title, spaceUUID)
        replace(pinned.tab)
        replace(pinned.space)
        if case .tab(let tab) = pinned.tab.body { return tab }
        return nil
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
