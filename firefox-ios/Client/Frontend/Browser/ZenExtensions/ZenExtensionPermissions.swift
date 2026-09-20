// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import WebKit

/// Turns an extension's requested permissions into the lines shown in the
/// install prompt, in the browser's words rather than the manifest's.
enum ZenExtensionPermissions {
    /// What the extension asks for, most far-reaching first.
    static func summary(of webExtension: WKWebExtension) -> [String] {
        var lines: [String] = []
        if let hosts = hostAccess(webExtension.allRequestedMatchPatterns) {
            lines.append(hosts)
        }
        lines += webExtension.requestedPermissions
            .compactMap(description)
            .sorted()
        return lines
    }

    static func hostAccess(_ patterns: Set<WKWebExtension.MatchPattern>) -> String? {
        guard !patterns.isEmpty else { return nil }
        if patterns.contains(where: { $0.matchesAllURLs || $0.matchesAllHosts }) {
            return "Read and change your data on every site you visit"
        }
        let hosts = Set(patterns.compactMap { $0.host }).sorted()
        guard !hosts.isEmpty else { return "Read and change your data on some sites" }
        if hosts.count <= 3 {
            return "Read and change your data on \(hosts.joined(separator: ", "))"
        }
        return "Read and change your data on \(hosts.count) sites"
    }

    /// `nil` for permissions with no user-visible consequence worth listing.
    static func description(_ permission: WKWebExtension.Permission) -> String? {
        switch permission {
        case .tabs: return "See the tabs you have open"
        case .activeTab: return "See the tab you are using when you run it"
        case .cookies: return "Read and change cookies"
        case .webNavigation: return "See where your tabs navigate"
        case .webRequest: return "See and change the requests pages make"
        case .declarativeNetRequest, .declarativeNetRequestWithHostAccess: return "Block content on pages"
        case .declarativeNetRequestFeedback: return "See what it blocked"
        case .scripting: return "Run scripts on pages"
        case .clipboardWrite: return "Write to the clipboard"
        case .nativeMessaging: return "Talk to apps on your device"
        case .contextMenus, .menus: return "Add items to menus"
        case .alarms, .storage, .unlimitedStorage: return nil
        default: return permission.rawValue
        }
    }
}
