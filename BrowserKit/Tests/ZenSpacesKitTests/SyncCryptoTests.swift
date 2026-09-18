// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest
@testable import ZenSpacesKit

final class SyncCryptoTests: XCTestCase {
    // Generated independently with `openssl enc -aes-256-cbc` and
    // `openssl dgst -sha256 -mac HMAC` over the base64 ciphertext.
    private let syncKey = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8g"
        + "ISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0-Pw"
    private let vector = EncryptedPayload(
        ciphertext: "ppP/DT+lpfigXBnc6BZSbcN68QOwpHlxB2bGPghNUpC4t/gzF+tWuZDw4eT8Ux6/"
            + "dclGXPdv5VDwsR1KjMViwi0R8woCQ0BiAggC04UUdSI=",
        iv: "oKGio6SlpqeoqaqrrK2urw==",
        hmac: "bd5b1beac7973cbb9a618fc8e5d4b230503be499cd33085f643997277c9b017f"
    )

    func testSyncKeySplitsIntoEncryptionThenHMACKey() throws {
        let bundle = try KeyBundle(syncKey: syncKey)
        XCTAssertEqual(bundle.encryptionKey, Data(0x00...0x1f))
        XCTAssertEqual(bundle.hmacKey, Data(0x20...0x3f))
    }

    func testDecryptsOpenSSLVector() throws {
        let cleartext = try KeyBundle(syncKey: syncKey).decrypt(vector)
        XCTAssertEqual(String(decoding: cleartext, as: UTF8.self),
                       #"{"id":"layout","kind":"layout","data":{"spaces":["s1"],"essentials":{}}}"#)
    }

    func testAcceptsUppercaseHMAC() throws {
        let upper = EncryptedPayload(ciphertext: vector.ciphertext, iv: vector.iv, hmac: vector.hmac.uppercased())
        XCTAssertNoThrow(try KeyBundle(syncKey: syncKey).decrypt(upper))
    }

    func testRejectsTamperedHMAC() {
        let tampered = EncryptedPayload(ciphertext: vector.ciphertext,
                                        iv: vector.iv,
                                        hmac: String(repeating: "0", count: 64))
        XCTAssertThrowsError(try KeyBundle(syncKey: syncKey).decrypt(tampered)) { error in
            XCTAssertEqual(error as? SyncCryptoError, .hmacMismatch)
        }
    }

    func testRejectsWrongKeyLength() {
        XCTAssertThrowsError(try KeyBundle(syncKey: "AAEC")) { error in
            XCTAssertEqual(error as? SyncCryptoError, .badKeyLength(3))
        }
    }

    func testCollectionKeysPreferPerCollectionBundle() throws {
        let defaultPair = [Data(repeating: 1, count: 32), Data(repeating: 2, count: 32)].map { $0.base64EncodedString() }
        let spacesPair = [Data(repeating: 3, count: 32), Data(repeating: 4, count: 32)].map { $0.base64EncodedString() }
        let json = try JSONSerialization.data(withJSONObject: [
            "id": "keys", "collection": "crypto",
            "default": defaultPair,
            "collections": ["spaces": spacesPair],
        ])
        let keys = try CollectionKeys(cleartext: json)
        XCTAssertEqual(keys.bundle(for: "spaces").encryptionKey, Data(repeating: 3, count: 32))
        XCTAssertEqual(keys.bundle(for: "tabs").encryptionKey, Data(repeating: 1, count: 32))
    }
}

final class HawkTests: XCTestCase {
    // The worked example from the Hawk specification, confirmed with
    // `openssl dgst -sha256 -hmac`.
    func testSpecificationExample() throws {
        let header = Hawk.authorizationHeader(
            credentials: HawkCredentials(id: "dh37fgj492je",
                                         key: Data("werxhqb98rpaxn39848xrunpaw3489ruxnpa98w4rxn".utf8)),
            method: "get",
            url: try XCTUnwrap(URL(string: "http://example.com:8000/resource/1?b=1&a=2")),
            timestamp: 1353832234,
            nonce: "j4h3g2",
            ext: "some-app-ext-data"
        )
        let expected = #"Hawk id="dh37fgj492je", ts="1353832234", nonce="j4h3g2", "#
            + #"ext="some-app-ext-data", mac="6R4rV5iE+NPoym+WwjeHzjAGXUtLNIxmo1vpMofpLAE=""#
        XCTAssertEqual(header, expected)
    }
}

final class TokenserverEndpointTests: XCTestCase {
    func testAddsSyncSuffixOnlyWhenMissing() throws {
        let cases = [
            "https://token.services.mozilla.com/": "https://token.services.mozilla.com/1.0/sync/1.5",
            "https://token.services.mozilla.com/1.0/sync/1.5": "https://token.services.mozilla.com/1.0/sync/1.5",
            "https://token.services.mozilla.com/1.0/sync/1.5/": "https://token.services.mozilla.com/1.0/sync/1.5",
            "http://example.com/token": "http://example.com/token/1.0/sync/1.5",
        ]
        for (input, expected) in cases {
            let url = SyncStorageClient.tokenserverEndpoint(try XCTUnwrap(URL(string: input)))
            XCTAssertEqual(url.absoluteString, expected, input)
        }
    }
}
