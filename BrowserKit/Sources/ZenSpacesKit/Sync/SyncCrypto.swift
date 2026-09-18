// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import CommonCrypto
import CryptoKit
import Foundation

public enum SyncCryptoError: Error, Equatable {
    case badKeyLength(Int)
    case badBase64
    case hmacMismatch
    case decryptionFailed(Int32)
}

/// The encrypted envelope of a Sync 1.5 record payload.
public struct EncryptedPayload: Decodable, Sendable, Equatable {
    public let ciphertext: String
    public let iv: String
    public let hmac: String

    enum CodingKeys: String, CodingKey {
        case ciphertext
        case iv = "IV"
        case hmac
    }

    public init(ciphertext: String, iv: String, hmac: String) {
        self.ciphertext = ciphertext
        self.iv = iv
        self.hmac = hmac
    }
}

/// An AES-256 key plus an HMAC-SHA256 key, as Sync 1.5 pairs them
/// (storage format 5, "legacy" AES-CBC + HMAC).
public struct KeyBundle: Sendable, Equatable {
    public let encryptionKey: Data
    public let hmacKey: Data

    public init(encryptionKey: Data, hmacKey: Data) throws {
        guard encryptionKey.count == 32 else { throw SyncCryptoError.badKeyLength(encryptionKey.count) }
        guard hmacKey.count == 32 else { throw SyncCryptoError.badKeyLength(hmacKey.count) }
        self.encryptionKey = encryptionKey
        self.hmacKey = hmacKey
    }

    /// The account's kSync (the `k` of the oldsync scoped key, base64url):
    /// first 32 bytes encrypt, last 32 authenticate.
    public init(syncKey base64URL: String) throws {
        guard let bytes = Data(base64URLEncoded: base64URL) else { throw SyncCryptoError.badBase64 }
        guard bytes.count == 64 else { throw SyncCryptoError.badKeyLength(bytes.count) }
        try self.init(encryptionKey: bytes.prefix(32), hmacKey: bytes.suffix(32))
    }

    public init(base64EncryptionKey: String, base64HMACKey: String) throws {
        guard let enc = Data(base64Encoded: base64EncryptionKey),
              let mac = Data(base64Encoded: base64HMACKey)
        else { throw SyncCryptoError.badBase64 }
        try self.init(encryptionKey: enc, hmacKey: mac)
    }

    /// The HMAC covers the base64 text of the ciphertext, not its bytes.
    public func decrypt(_ payload: EncryptedPayload) throws -> Data {
        guard let ciphertext = Data(base64Encoded: payload.ciphertext),
              let iv = Data(base64Encoded: payload.iv),
              let expected = Data(hexEncoded: payload.hmac)
        else { throw SyncCryptoError.badBase64 }

        let authenticated = Data(ciphertext.base64EncodedString().utf8)
        guard HMAC<SHA256>.isValidAuthenticationCode(expected,
                                                     authenticating: authenticated,
                                                     using: SymmetricKey(data: hmacKey))
        else { throw SyncCryptoError.hmacMismatch }

        return try aes256CBCDecrypt(ciphertext, iv: iv)
    }

    private func aes256CBCDecrypt(_ ciphertext: Data, iv: Data) throws -> Data {
        var output = Data(count: ciphertext.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var written = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            ciphertext.withUnsafeBytes { inputBytes in
                iv.withUnsafeBytes { ivBytes in
                    encryptionKey.withUnsafeBytes { keyBytes in
                        CCCrypt(CCOperation(kCCDecrypt),
                                CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(kCCOptionPKCS7Padding),
                                keyBytes.baseAddress,
                                encryptionKey.count,
                                ivBytes.baseAddress,
                                inputBytes.baseAddress,
                                ciphertext.count,
                                outputBytes.baseAddress,
                                outputCapacity,
                                &written)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw SyncCryptoError.decryptionFailed(status) }
        return output.prefix(written)
    }
}

/// The decrypted `crypto/keys` record: a default bundle plus optional
/// per-collection overrides.
public struct CollectionKeys: Sendable, Equatable {
    public let defaultBundle: KeyBundle
    public let collections: [String: KeyBundle]

    public init(cleartext: Data) throws {
        struct Raw: Decodable {
            let `default`: [String]
            let collections: [String: [String]]?
        }
        let raw = try JSONDecoder().decode(Raw.self, from: cleartext)
        defaultBundle = try Self.bundle(raw.default)
        collections = try (raw.collections ?? [:]).mapValues(Self.bundle)
    }

    public func bundle(for collection: String) -> KeyBundle {
        collections[collection] ?? defaultBundle
    }

    private static func bundle(_ pair: [String]) throws -> KeyBundle {
        guard pair.count == 2 else { throw SyncCryptoError.badKeyLength(pair.count) }
        return try KeyBundle(base64EncryptionKey: pair[0], base64HMACKey: pair[1])
    }
}

extension Data {
    init?(base64URLEncoded string: String) {
        var base64 = string.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }

    init?(hexEncoded string: String) {
        guard string.count.isMultiple(of: 2) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(string.count / 2)
        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(index, offsetBy: 2)
            guard let byte = UInt8(string[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
