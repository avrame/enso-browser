// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import ZenSpacesKit
import class MozillaAppServices.FxAccountManager
import enum MozillaAppServices.OAuthScope

enum ZenSpacesAuthError: Error, CustomStringConvertible {
    case notSignedIn
    case needsReauthentication
    case noScopedKey

    var description: String {
        switch self {
        case .notSignedIn: return "Sign in to your Mozilla account first (Settings → Sync)."
        case .needsReauthentication: return "Your Mozilla account needs you to sign in again."
        case .noScopedKey: return "The account did not provide a Sync key."
        }
    }
}

/// Builds Sync storage credentials from the signed-in Mozilla account,
/// the same way `RustSyncManager` does for Mozilla's own engines.
struct ZenSpacesAuthProvider {
    let accountManager: FxAccountManager?

    @MainActor
    func auth() async throws -> SyncAuth {
        guard let accountManager, accountManager.hasAccount() else { throw ZenSpacesAuthError.notSignedIn }
        guard !accountManager.accountNeedsReauth() else { throw ZenSpacesAuthError.needsReauthentication }

        let tokenInfo = try await withCheckedThrowingContinuation { continuation in
            accountManager.getAccessToken(scope: OAuthScope.oldSync) { continuation.resume(with: $0) }
        }
        guard let key = tokenInfo.key else { throw ZenSpacesAuthError.noScopedKey }
        let tokenServerURL = try await withCheckedThrowingContinuation { continuation in
            accountManager.getTokenServerEndpointURL { continuation.resume(with: $0) }
        }
        return SyncAuth(accessToken: tokenInfo.token,
                        keyID: key.kid,
                        syncKey: key.k,
                        tokenServerURL: tokenServerURL)
    }
}
