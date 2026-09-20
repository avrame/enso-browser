// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import WebKit

extension Tab: WKWebExtensionTab {
    public func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        ZenWebExtensions.shared.window
    }

    public func indexInWindow(for context: WKWebExtensionContext) -> Int {
        ZenWebExtensions.shared.window?.tabs.firstIndex(of: self) ?? 0
    }

    public func webView(for context: WKWebExtensionContext) -> WKWebView? {
        webView
    }

    public func title(for context: WKWebExtensionContext) -> String? {
        displayTitle
    }

    public func url(for context: WKWebExtensionContext) -> URL? {
        url
    }

    public func isSelected(for context: WKWebExtensionContext) -> Bool {
        ZenWebExtensions.shared.window?.tabManager?.selectedTab === self
    }

    public func isLoadingComplete(for context: WKWebExtensionContext) -> Bool {
        webView?.isLoading == false
    }

    public func size(for context: WKWebExtensionContext) -> CGSize {
        webView?.bounds.size ?? .zero
    }

    public func activate(for context: WKWebExtensionContext) async throws {
        guard let tabManager = ZenWebExtensions.shared.window?.tabManager else { return }
        tabManager.selectTab(self, previous: tabManager.selectedTab)
    }

    public func close(for context: WKWebExtensionContext) async throws {
        ZenWebExtensions.shared.window?.tabManager?.removeTab(tabUUID)
    }

    public func loadURL(_ url: URL, for context: WKWebExtensionContext) async throws {
        _ = loadRequest(URLRequest(url: url))
    }

    public func reload(fromOrigin: Bool, for context: WKWebExtensionContext) async throws {
        reload(bypassCache: fromOrigin)
    }

    public func goBack(for context: WKWebExtensionContext) async throws {
        goBack()
    }

    public func goForward(for context: WKWebExtensionContext) async throws {
        goForward()
    }
}
