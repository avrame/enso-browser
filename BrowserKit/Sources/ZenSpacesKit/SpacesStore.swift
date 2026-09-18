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

    private let cache: SpacesCache
    private let fetch: @MainActor () async throws -> SpacesFetchResult

    public init(cache: SpacesCache, fetch: @escaping @MainActor () async throws -> SpacesFetchResult) {
        self.cache = cache
        self.fetch = fetch
        if let cached = cache.load() {
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
            snapshot = result.snapshot
            fetchedAt = result.fetchedAt
            status = .idle
            try? cache.save(result.records, fetchedAt: result.fetchedAt)
        } catch {
            status = .failed(String(describing: error))
        }
    }

    /// Forgets everything, e.g. after the account signs out.
    public func reset() {
        cache.clear()
        snapshot = nil
        fetchedAt = nil
        status = .idle
    }
}
