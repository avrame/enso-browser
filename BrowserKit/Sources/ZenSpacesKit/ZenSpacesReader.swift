// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

public enum ZenSpacesError: Error, Equatable, CustomStringConvertible {
    /// meta/global has no `spaces` engine: no Zen device has synced spaces yet.
    case engineNotOnServer
    /// A newer Zen changed the format; reading it could misinterpret data.
    case engineVersionTooNew(Int)

    public var description: String {
        switch self {
        case .engineNotOnServer:
            return "No Zen device has synced spaces to this account. In Zen: Settings → Sync → Sync your Spaces."
        case .engineVersionTooNew(let version):
            return "Zen's spaces format is version \(version); this app reads up to \(ZenSpacesReader.supportedEngineVersion)."
        }
    }
}

public struct SpacesFetchResult: Sendable {
    public let records: [SpacesRecord]
    public let snapshot: SpacesSnapshot
    public let engineVersion: Int
    public let fetchedAt: Date

    public init(records: [SpacesRecord], snapshot: SpacesSnapshot, engineVersion: Int, fetchedAt: Date) {
        self.records = records
        self.snapshot = snapshot
        self.engineVersion = engineVersion
        self.fetchedAt = fetchedAt
    }
}

/// Reads Zen's `spaces` collection. Read-only: nothing here writes to the
/// server, including meta/global.
public struct ZenSpacesReader: Sendable {
    public static let collection = "spaces"
    public static let supportedEngineVersion = 3

    private let client: SyncStorageClient

    public init(auth: SyncAuth, transport: HTTPTransport = URLSessionTransport()) {
        self.client = SyncStorageClient(auth: auth, transport: transport)
    }

    public func fetch() async throws -> SpacesFetchResult {
        let meta = try await client.metaGlobal()
        guard let engine = meta.engines[Self.collection] else { throw ZenSpacesError.engineNotOnServer }
        guard engine.version <= Self.supportedEngineVersion else {
            throw ZenSpacesError.engineVersionTooNew(engine.version)
        }

        let records = try await client.decryptedRecords(in: Self.collection).map { bso, cleartext in
            let modified = Date(timeIntervalSince1970: bso.modified)
            switch cleartext {
            case .success(let data):
                return SpacesRecord(id: bso.id, modified: modified, cleartext: data)
            case .failure(let error):
                return SpacesRecord(id: bso.id,
                                    modified: modified,
                                    body: .malformed(reason: "undecryptable: \(error)"),
                                    raw: nil)
            }
        }
        return SpacesFetchResult(records: records,
                                 snapshot: SpacesSnapshot(records: records),
                                 engineVersion: engine.version,
                                 fetchedAt: Date())
    }
}
