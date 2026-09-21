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

/// Whether this browser uses Mozilla's Suggest service.
///
/// Firefox Suggest sends what someone types to Mozilla's servers and carries
/// sponsored results that Mozilla is paid for. Both are reasonable things for
/// Firefox to do and neither is Ensō's to offer: the suggestions are not ours
/// to give and the sponsorship is not ours to take, and a browser whose
/// privacy notice says it collects nothing should not be sending keystrokes
/// to a company its users have no relationship with.
///
/// History, bookmarks and synced tabs still complete as you type. Those never
/// leave the device.
enum EnsoSuggest {
    static let usesMozillaSuggest = false
}
