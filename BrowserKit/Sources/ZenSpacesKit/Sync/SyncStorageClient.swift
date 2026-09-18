// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

/// What the Mozilla account layer supplies to reach Sync storage.
public struct SyncAuth: Sendable {
    /// OAuth access token for the `oldsync` scope.
    public let accessToken: String
    /// The scoped key's `kid`, sent to the tokenserver as `X-KeyID`.
    public let keyID: String
    /// The scoped key's `k` (kSync, base64url).
    public let syncKey: String
    public let tokenServerURL: URL

    public init(accessToken: String, keyID: String, syncKey: String, tokenServerURL: URL) {
        self.accessToken = accessToken
        self.keyID = keyID
        self.syncKey = syncKey
        self.tokenServerURL = tokenServerURL
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

public enum SyncStorageError: Error, Equatable, CustomStringConvertible {
    case tokenserver(status: Int)
    case storage(status: Int, path: String)
    case notFound(path: String)
    /// A conditional write lost to a newer server copy; nothing was written.
    case modifiedSince(path: String)
    case malformedResponse(String)

    public var description: String {
        switch self {
        case .tokenserver(let status): return "Tokenserver returned HTTP \(status)"
        case .storage(let status, let path): return "Sync storage returned HTTP \(status) for \(path)"
        case .notFound(let path): return "\(path) is not on the server"
        case .modifiedSince(let path): return "\(path) changed on the server while it was being written"
        case .malformedResponse(let what): return "Malformed response: \(what)"
        }
    }
}

/// A Sync 1.5 "basic storage object".
public struct BSO: Decodable, Sendable, Equatable {
    public let id: String
    public let modified: Double
    public let payload: String
}

public struct MetaGlobal: Sendable, Equatable {
    public struct Engine: Decodable, Sendable, Equatable {
        public let version: Int
        public let syncID: String?
    }

    public let storageVersion: Int?
    public let engines: [String: Engine]
    public let declined: [String]
}

/// Read-only Sync 1.5 storage access: tokenserver exchange, Hawk-signed
/// GETs, and decryption with the account's collection keys.
public actor SyncStorageClient {
    private struct Token: Decodable {
        let id: String
        let key: String
        let apiEndpoint: String

        enum CodingKeys: String, CodingKey {
            case id, key
            case apiEndpoint = "api_endpoint"
        }
    }

    private struct Session {
        let credentials: HawkCredentials
        let apiEndpoint: URL
        let clockSkew: TimeInterval
    }

    private let auth: SyncAuth
    private let transport: HTTPTransport
    private var session: Session?
    private var collectionKeys: CollectionKeys?

    public init(auth: SyncAuth, transport: HTTPTransport = URLSessionTransport()) {
        self.auth = auth
        self.transport = transport
    }

    public func metaGlobal() async throws -> MetaGlobal {
        struct Payload: Decodable {
            let storageVersion: Int?
            let engines: [String: MetaGlobal.Engine]?
            let declined: [String]?
        }
        let bso = try await getBSO("meta/global")
        let payload = try JSONDecoder().decode(Payload.self, from: Data(bso.payload.utf8))
        return MetaGlobal(storageVersion: payload.storageVersion,
                          engines: payload.engines ?? [:],
                          declined: payload.declined ?? [])
    }

    /// Every record in the collection, decrypted. Records that fail to
    /// decrypt are returned as errors, not thrown, so one bad record does
    /// not hide the rest.
    public func decryptedRecords(in collection: String) async throws -> [(bso: BSO, cleartext: Result<Data, Error>)] {
        let bundle = try await keys().bundle(for: collection)
        return try await allBSOs(in: collection).map { bso in
            (bso, Result {
                let envelope = try JSONDecoder().decode(EncryptedPayload.self, from: Data(bso.payload.utf8))
                return try bundle.decrypt(envelope)
            })
        }
    }

    /// One record, decrypted, with the BSO carrying its server timestamp.
    public func record(id: String, in collection: String) async throws -> (bso: BSO, cleartext: Data) {
        let bundle = try await keys().bundle(for: collection)
        let bso = try await getBSO("\(collection)/\(id)")
        let envelope = try JSONDecoder().decode(EncryptedPayload.self, from: Data(bso.payload.utf8))
        return (bso, try bundle.decrypt(envelope))
    }

    /// Encrypts and stores one record, only if the server copy is still the
    /// one last modified at `ifUnmodifiedSince`; otherwise throws
    /// `.modifiedSince` and writes nothing. Returns the new server timestamp.
    public func put(id: String,
                    in collection: String,
                    cleartext: Data,
                    ifUnmodifiedSince: Double) async throws -> Double {
        let bundle = try await keys().bundle(for: collection)
        let envelope = try bundle.encrypt(cleartext)
        let payload = String(decoding: try JSONEncoder().encode(envelope), as: UTF8.self)
        let body = try JSONEncoder().encode(["id": id, "payload": payload])
        let condition = ["X-If-Unmodified-Since": Self.timestamp(ifUnmodifiedSince)]
        let path = "storage/\(collection)/\(id)"
        let (data, response) = try await send("PUT", path, query: [], body: body, headers: condition)
        let modified = response.value(forHTTPHeaderField: "X-Last-Modified").flatMap(Double.init)
            ?? Double(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        guard let modified else { throw SyncStorageError.malformedResponse("PUT without a timestamp") }
        return modified
    }

    /// Sync timestamps are decimal seconds with two fractional digits.
    static func timestamp(_ seconds: Double) -> String {
        String(format: "%.2f", seconds)
    }

    private func keys() async throws -> CollectionKeys {
        if let collectionKeys { return collectionKeys }
        let bso = try await getBSO("crypto/keys")
        let envelope = try JSONDecoder().decode(EncryptedPayload.self, from: Data(bso.payload.utf8))
        let cleartext = try KeyBundle(syncKey: auth.syncKey).decrypt(envelope)
        let keys = try CollectionKeys(cleartext: cleartext)
        collectionKeys = keys
        return keys
    }

    private func allBSOs(in collection: String) async throws -> [BSO] {
        var result: [BSO] = []
        var offset: String?
        repeat {
            var query = [URLQueryItem(name: "full", value: "1"), URLQueryItem(name: "limit", value: "1000")]
            if let offset {
                query.append(URLQueryItem(name: "offset", value: offset))
            }
            let (data, response) = try await send("GET", "storage/\(collection)", query: query)
            result += try JSONDecoder().decode([BSO].self, from: data)
            offset = response.value(forHTTPHeaderField: "X-Weave-Next-Offset")
        } while offset != nil
        return result
    }

    private func getBSO(_ path: String) async throws -> BSO {
        let (data, _) = try await send("GET", "storage/\(path)", query: [])
        return try JSONDecoder().decode(BSO.self, from: data)
    }

    private func send(_ method: String,
                      _ path: String,
                      query: [URLQueryItem],
                      body: Data? = nil,
                      headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        let session = try await currentSession()
        var components = URLComponents(url: session.apiEndpoint.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query
        }
        guard let url = components?.url else { throw SyncStorageError.malformedResponse("storage URL for \(path)") }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue(Hawk.authorizationHeader(credentials: session.credentials,
                                                  method: method,
                                                  url: url,
                                                  timestamp: Int(Date().timeIntervalSince1970 + session.clockSkew),
                                                  nonce: Hawk.makeNonce()),
                         forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.send(request)
        switch response.statusCode {
        case 200..<300: return (data, response)
        case 404: throw SyncStorageError.notFound(path: path)
        case 412: throw SyncStorageError.modifiedSince(path: path)
        default: throw SyncStorageError.storage(status: response.statusCode, path: path)
        }
    }

    private func currentSession() async throws -> Session {
        if let session { return session }

        var request = URLRequest(url: Self.tokenserverEndpoint(auth.tokenServerURL))
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(auth.keyID, forHTTPHeaderField: "X-KeyID")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw SyncStorageError.tokenserver(status: response.statusCode)
        }
        let token = try JSONDecoder().decode(Token.self, from: data)
        guard let apiEndpoint = URL(string: token.apiEndpoint) else {
            throw SyncStorageError.malformedResponse("api_endpoint \(token.apiEndpoint)")
        }
        let serverTime = response.value(forHTTPHeaderField: "X-Timestamp").flatMap(TimeInterval.init)
        let session = Session(credentials: HawkCredentials(id: token.id, key: Data(token.key.utf8)),
                              apiEndpoint: apiEndpoint,
                              clockSkew: serverTime.map { $0 - Date().timeIntervalSince1970 } ?? 0)
        self.session = session
        return session
    }

    /// The account's tokenserver URL may or may not already end in the
    /// `1.0/sync/1.5` suffix; mirrors application-services' fixup.
    static func tokenserverEndpoint(_ base: URL) -> URL {
        let string = base.absoluteString
        if string.hasSuffix("1.0/sync/1.5") { return base }
        if string.hasSuffix("1.0/sync/1.5/") { return URL(string: String(string.dropLast())) ?? base }
        let trimmed = string.hasSuffix("/") ? String(string.dropLast()) : string
        return URL(string: trimmed + "/1.0/sync/1.5") ?? base
    }
}
