// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

/// Whether this browser reports how it is used.
///
/// Ensō is not Firefox, and its users have no relationship with Mozilla:
/// collecting their browsing under Ensō's name and sending it to Mozilla's
/// servers would be neither honest nor ours to do. So Glean is initialised
/// with uploading off, the daily usage ping — which ignores the usage-data
/// preference by design — never starts, and the settings that would promise
/// otherwise are not shown.
///
/// Turning this on means having somewhere of our own for the pings to go,
/// and saying so in the onboarding text and the privacy notice first.
enum EnsoTelemetry {
    static let reportsUsageData = false
}
