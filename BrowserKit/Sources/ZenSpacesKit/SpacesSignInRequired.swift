// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

/// Thrown by a fetch that cannot run because no account is signed in, or
/// because the signed-in one needs authenticating again.
///
/// It is not an error to show: spaces live in the account, so without one
/// there is nothing to read and nothing has gone wrong. The sheet offers a
/// way to sign in instead.
public struct SpacesSignInRequired: Error {
    public init() {}
}
