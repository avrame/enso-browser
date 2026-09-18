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

public enum ZenSpacesWriteError: Error, Equatable, CustomStringConvertible {
    /// Writes are only safe against the exact format this client knows.
    case unsupportedEngineVersion(Int?)
    case recordNotFound(String)
    case unexpectedRecord(id: String, reason: String)
    case invalidName
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
        case .conflict: return "It kept changing on another device. Try again."
        }
    }
}

/// Changes Zen records on the server one field at a time. Every write
/// re-reads the server copy, changes only the named field, keeps every
/// other field as received (including ones this client does not model),
/// and is conditional on that copy being unchanged. Never deletes.
public struct ZenSpacesWriter: Sendable {
    private let client: SyncStorageClient
    private let maxAttempts = 3

    public init(auth: SyncAuth, transport: HTTPTransport = URLSessionTransport()) {
        self.client = SyncStorageClient(auth: auth, transport: transport)
    }

    /// Spaces and folders both keep their name in `data.name`.
    public func rename(_ target: RenameTarget, to name: String) async throws -> SpacesRecord {
        let name = try Self.validName(name)
        return try await update(id: target.id, kind: target.kind) { data in
            data["name"] = .string(name)
        }
    }

    public static func validName(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ZenSpacesWriteError.invalidName }
        return name
    }

    private func update(id: String,
                        kind: String,
                        change: @Sendable (inout [String: JSONValue]) -> Void) async throws -> SpacesRecord {
        let meta = try await client.metaGlobal()
        let version = meta.engines[ZenSpacesReader.collection]?.version
        guard version == ZenSpacesReader.supportedEngineVersion else {
            throw ZenSpacesWriteError.unsupportedEngineVersion(version)
        }

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
