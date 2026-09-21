// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import UIKit

/// Utility functions related to SUMO and Webcompat
public struct SupportUtils {
    /// Mozilla's support pages document Firefox, not Ensō, and being sent
    /// there implies a support relationship that does not exist. Until Ensō
    /// has pages of its own, these are nil and the links that use them are
    /// simply not shown.
    public static var URLForPrivateBrowsingLearnMore: URL? {
        return nil
    }

    /// Where Ensō is actually developed, and where a problem with it can
    /// usefully be reported.
    public static var URLForGetHelp: URL? {
        return URL(string: "https://github.com/avrame/firefox-ios/issues")
    }

    public static var URLForPocketLearnMore: URL? {
        // Returns the predefined URL associated to homepage Pocket's Learn more action.
        return URL(string: "https://www.mozilla.org/firefox/pocket/?utm_source=ff_ios")
    }

    /// Ensō's own documents, served from the app. Mozilla's legal pages
    /// describe Firefox and are not this browser's to present as its own.
    public static var URLForTermsOfUse: URL? {
        return URL(string: "\(InternalURL.baseUrl)/about/terms")
    }

    public static var URLForPrivacyNotice: URL? {
        return URL(string: "\(InternalURL.baseUrl)/about/privacy")
    }

    public static var URLForUpdatedPrivacyNotice: URL? {
        return URLForPrivacyNotice
    }

    public static var URLForUpdatedPrivacyNoticeDiff: URL? {
        return URLForPrivacyNotice
    }

    public static var URLForRelayAccountManagement: URL? {
        return URL(string: "https://relay.firefox.com/accounts/profile")
    }

    public static var URLForRelayMaskLearnMoreArticle: URL? {
        return URL(string: "https://support.mozilla.org/en-US/kb/relay-masks-ios")
    }

    public static var URLForConnectionNotSecureLearnMore: URL? {
        return nil
    }

    /// A SUMO topic is an article about Firefox on Mozilla's site. Ensō has
    /// no equivalent yet, so callers get nothing and hide their link.
    public static func URLForTopic(_ topic: String, useMobilePath: Bool = true) -> URL? {
        return nil
    }

    /// The campaign parameters were for Mozilla's analytics; Ensō's notice is
    /// a page in the app, so they have nothing to attach to.
    public static func URLForPrivacyNotice(source: String, campaign: String, content: String?) -> URL? {
        return URLForPrivacyNotice
    }

    private static func legacyPrivacyNotice(source: String, campaign: String, content: String?) -> URL? {
        let defaultURL = URLForPrivacyNotice

        guard let languageIdentifier = Locale.preferredLanguages.first else {
            return defaultURL
        }

        var privacyNoticeString =
                    "https://www.mozilla.org/\(languageIdentifier)/privacy/firefox/?utm_medium=firefox-mobile&utm_source=\(source)&utm_campaign=\(campaign)"

        if let content {
            privacyNoticeString.append("&utm_content=\(content)")
        }

        return URL(string: privacyNoticeString) ?? defaultURL
    }
}
