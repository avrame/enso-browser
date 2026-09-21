// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import WebKit

/// The browser window as extensions see it: the normal tabs of one tab
/// manager. Private tabs are deliberately invisible to extensions.
///
/// There is one window, not one per space, because spaces do not own tabs
/// yet: the tab list is flat, and a tab opened from a space is only linked
/// back to its pinned entry. A window per space would describe a structure
/// the user cannot see or switch between. See ZEN-EXTENSIONS.md for when to
/// revisit this.
@MainActor
final class ZenExtensionWindow: NSObject, WKWebExtensionWindow {
    private(set) weak var tabManager: TabManager?

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    var tabs: [Tab] { tabManager?.normalTabs ?? [] }

    func openTab(url: URL?, selected: Bool) -> Tab? {
        guard let tabManager else { return nil }
        let request = url.map { URLRequest(url: $0) }
        let tab = tabManager.addTab(request, afterTab: nil, zombie: false, isPrivate: false)
        if selected {
            tabManager.selectTab(tab, previous: tabManager.selectedTab)
        }
        return tab
    }

    /// WebKit wires extensions into a web view when it is created, so pages
    /// already on screen stay outside the extension until their web view is
    /// rebuilt. Session data is committed first so nothing is lost.
    func restartWebViews() async {
        guard let tabManager else { return }
        tabManager.commitChanges()
        let selected = tabManager.selectedTab
        for tab in tabs where tab.webView != nil {
            await tab.offloadWebView()
        }
        if let selected, !selected.isPrivate {
            tabManager.selectTab(selected, previous: nil)
        }
    }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        tabs
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        guard let selected = tabManager?.selectedTab, !selected.isPrivate else { return nil }
        return selected
    }

    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType {
        .normal
    }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        .maximized
    }

    func isPrivate(for context: WKWebExtensionContext) -> Bool {
        false
    }

    func frame(for context: WKWebExtensionContext) -> CGRect {
        screenFrame(for: context)
    }

    func screenFrame(for context: WKWebExtensionContext) -> CGRect {
        UIScreen.main.bounds
    }
}
