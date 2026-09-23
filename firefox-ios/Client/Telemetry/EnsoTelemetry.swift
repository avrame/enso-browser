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

/// Whether this browser registers for remote push notifications.
///
/// Firefox uses push for one thing on iOS: receiving a tab sent from another
/// device. Getting it means registering a device token with Mozilla's push
/// service, which is a flow to Mozilla that the privacy notice does not
/// mention, for a convenience Ensō can live without in its first release. The
/// entitlement also has to be provisioned, and an entitlement nothing uses is
/// one more thing for a reviewer to ask about.
///
/// Tabs you send *from* Ensō still arrive elsewhere; it is only the receiving
/// end that is asleep. The NotificationService extension has nothing to do
/// while this is off.
enum EnsoPush {
    static let isEnabled = false
}

/// Whether Ensō can be set as the default browser.
///
/// iOS only offers the choice for apps holding
/// `com.apple.developer.web-browser`, which Apple grants by request. Until
/// that request is approved the entitlement is not in the build, so every
/// invitation to "set Ensō as your default" leads to a Settings page with no
/// such option on it - a button that cannot do what it says.
///
/// Turn this on in the same change that adds the entitlement back to
/// EnsoApplication.entitlements, not before.
enum EnsoDefaultBrowser {
    static let canBeDefault = false
}

/// Whether the homepage carries sponsored shortcuts.
///
/// These are a separate arrangement from Suggest - a different service, fetched
/// from Mozilla's ad provider and reported back with impressions and clicks -
/// but the objection is the same one: the money is Mozilla's to take and not
/// ours, and a homepage that reports what its shortcuts showed you sits badly
/// beside a privacy notice promising nothing is collected.
///
/// Your own most-visited sites still fill the row. Those come from history on
/// the device.
enum EnsoSponsoredShortcuts {
    static let areOffered = false
}
