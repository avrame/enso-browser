// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import WebKit

/// Runs WebExtensions (iOS 18.4+ `WKWebExtension`).
///
/// One controller is shared by every normal tab's web view; the browser
/// window is presented to extensions as a single `WKWebExtensionWindow`
/// whose tabs are the tab manager's normal tabs.
@MainActor
final class ZenWebExtensions: NSObject {
    static let shared = ZenWebExtensions()

    let controller = WKWebExtensionController(configuration: .default())
    private(set) var window: ZenExtensionWindow?
    private let logger: Logger
    /// Tabs already announced to WebKit. Extension APIs reject a web view
    /// whose tab it has never seen.
    private var knownTabs = Set<ObjectIdentifier>()
    /// Packages in the store that would not load, for the settings screen.
    private(set) var failures: [LoadFailure] = []

    var contexts: [WKWebExtensionContext] {
        controller.extensionContexts.sorted { ($0.webExtension.displayName ?? "") < ($1.webExtension.displayName ?? "") }
    }

    init(logger: Logger = DefaultLogger.shared) {
        self.logger = logger
        super.init()
        controller.delegate = self
    }

    /// Presents `tabManager`'s window to extensions and keeps it up to date.
    func start(tabManager: TabManager) {
        guard window == nil else { return }
        let window = ZenExtensionWindow(tabManager: tabManager)
        self.window = window
        tabManager.addDelegate(self)
        controller.didOpenWindow(window)
        controller.didFocusWindow(window)
        registerExistingTabs()
        installTestExtensionIfRequested()
        Task { await loadInstalledExtensions() }
    }

    /// Loads every package in the store, newest state of disk wins.
    func loadInstalledExtensions() async {
        let packages: [URL]
        do {
            packages = try ZenExtensionStore.packages()
        } catch {
            logger.log("Could not read installed extensions: \(error)", level: .warning, category: .webview)
            return
        }
        failures = []
        for package in packages {
            do {
                try await install(resourceBaseURL: package)
            } catch {
                failures.append(LoadFailure(package: package.lastPathComponent,
                                            message: (error as NSError).localizedDescription))
                logger.log("Could not load \(package.lastPathComponent): \(error)", level: .warning, category: .webview)
            }
        }
    }

    /// An extension copied into the store and read, but not yet loaded:
    /// nothing runs until the user has seen what it asks for.
    struct PendingInstall {
        let webExtension: WKWebExtension
        let package: URL

        var name: String { webExtension.displayName ?? package.lastPathComponent }
        var permissions: [String] { ZenExtensionPermissions.summary(of: webExtension) }
    }

    /// Copies a package picked by the user into the store and reads its
    /// manifest. Pair every call with `commit` or `discard`.
    func prepare(package url: URL) async throws -> PendingInstall {
        let stored = try ZenExtensionStore.add(url)
        do {
            return PendingInstall(webExtension: try await WKWebExtension(resourceBaseURL: stored), package: stored)
        } catch {
            try? ZenExtensionStore.remove(stored)
            throw error
        }
    }

    /// Loads a prepared extension, granting what it asked for.
    @discardableResult
    func commit(_ pending: PendingInstall) async throws -> WKWebExtensionContext {
        do {
            return try await install(resourceBaseURL: pending.package,
                                     grantRequested: true,
                                     settleBackgroundContent: true)
        } catch {
            discard(pending)
            throw error
        }
    }

    /// Throws away a prepared extension the user did not allow.
    func discard(_ pending: PendingInstall) {
        try? ZenExtensionStore.remove(pending.package)
    }

    /// Waits for the background content's first run, then loads the context
    /// again so WebKit picks up what it registered.
    private func reload(_ context: WKWebExtensionContext) async {
        do {
            try await context.loadBackgroundContent()
            try controller.unload(context)
            try controller.load(context)
        } catch {
            logger.log("Could not reload \(context.uniqueIdentifier): \(error)", level: .warning, category: .webview)
        }
    }

    /// Unloads an extension and deletes its package.
    func remove(_ context: WKWebExtensionContext) throws {
        try controller.unload(context)
        let identifier = context.uniqueIdentifier
        ZenExtensionGrants.forget(identifier)
        for package in (try? ZenExtensionStore.packages()) ?? []
        where ZenExtensionStore.identifier(of: package) == identifier {
            try ZenExtensionStore.remove(package)
        }
    }

    private func registerExistingTabs() {
        for tab in window?.tabs ?? [] where !tab.isPrivate {
            register(tab)
        }
    }

    private func register(_ tab: Tab) {
        guard knownTabs.insert(ObjectIdentifier(tab)).inserted else { return }
        controller.didOpenTab(tab)
    }

    private func installTestExtensionIfRequested() {
#if MOZ_CHANNEL_developer
        guard ZenTestExtension.isRequested else { return }
        Task {
            do {
                try await install(resourceBaseURL: try ZenTestExtension.write())
            } catch {
                logger.log("Test extension failed: \(error)", level: .warning, category: .webview)
            }
        }
#endif
    }

    /// Loads the extension packaged at `url` (a directory or a ZIP/xpi).
    ///
    /// `grantRequested` belongs to a fresh install the user has just
    /// allowed. Later launches re-apply only what was allowed then, so
    /// nothing is granted behind the user's back.
    ///
    /// `settleBackgroundContent` is for a newly added extension: what its
    /// background content sets up on first run (enabled declarativeNetRequest
    /// rulesets, for one) only takes hold when the context loads, which for a
    /// mid-session install has already happened. Loading it a second time,
    /// once that first run is done, is what a relaunch would do.
    @discardableResult
    func install(resourceBaseURL url: URL,
                 grantRequested: Bool = false,
                 settleBackgroundContent: Bool = false) async throws -> WKWebExtensionContext {
        let webExtension = try await WKWebExtension(resourceBaseURL: url)
        if let existing = controller.extensionContext(for: webExtension) {
            return existing
        }
        let context = WKWebExtensionContext(for: webExtension)
        context.uniqueIdentifier = ZenExtensionStore.identifier(of: url)
        context.isInspectable = true
        try controller.load(context)
        // Granting only sticks once the context is loaded.
        if grantRequested {
            grantRequestedPermissions(in: context)
        } else {
            ZenExtensionGrants.apply(to: context)
        }
        logger.log("Loaded web extension \(webExtension.displayName ?? "?")", level: .info, category: .webview)
        if settleBackgroundContent, webExtension.hasBackgroundContent {
            await reload(context)
        }
        await window?.restartWebViews()
        return context
    }

    /// What the install prompt showed the user, granted once they allowed it
    /// and remembered for the next launch.
    private func grantRequestedPermissions(in context: WKWebExtensionContext) {
        let permissions = context.webExtension.requestedPermissions
        let patterns = context.webExtension.requestedPermissionMatchPatterns
        for permission in permissions {
            context.setPermissionStatus(.grantedExplicitly, for: permission)
        }
        for pattern in patterns {
            context.setPermissionStatus(.grantedExplicitly, for: pattern)
        }
        ZenExtensionGrants.allow(permissions: permissions, patterns: patterns, for: context.uniqueIdentifier)
    }
}

// MARK: - WKWebExtensionControllerDelegate

extension ZenWebExtensions: WKWebExtensionControllerDelegate {
    func webExtensionController(_ controller: WKWebExtensionController,
                                openWindowsFor context: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        window.map { [$0] } ?? []
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                focusedWindowFor context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        window
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                openNewTabUsing configuration: WKWebExtension.TabConfiguration,
                                for context: WKWebExtensionContext,
                                completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void) {
        guard let window else {
            completionHandler(nil, ZenWebExtensionError.noWindow)
            return
        }
        let tab = window.openTab(url: configuration.url, selected: configuration.shouldBeActive)
        completionHandler(tab, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                promptForPermissions permissions: Set<WKWebExtension.Permission>,
                                in tab: (any WKWebExtensionTab)?,
                                for context: WKWebExtensionContext,
                                completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void) {
        let details = permissions.compactMap(ZenExtensionPermissions.description).sorted()
        Task {
            let allowed = await ZenExtensionPrompt.allow(title: Self.askTitle(context), details: details)
            if allowed { ZenExtensionGrants.allow(permissions: permissions, for: context.uniqueIdentifier) }
            completionHandler(allowed ? permissions : [], nil)
        }
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                promptForPermissionToAccess urls: Set<URL>,
                                in tab: (any WKWebExtensionTab)?,
                                for context: WKWebExtensionContext,
                                completionHandler: @escaping (Set<URL>, Date?) -> Void) {
        let hosts = Set(urls.compactMap(\.host)).sorted()
        Task {
            let allowed = await ZenExtensionPrompt.allow(
                title: Self.askTitle(context),
                details: hosts.map { "Read and change your data on \($0)" }
            )
            completionHandler(allowed ? urls : [], nil)
        }
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                promptForPermissionMatchPatterns patterns: Set<WKWebExtension.MatchPattern>,
                                in tab: (any WKWebExtensionTab)?,
                                for context: WKWebExtensionContext,
                                completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void) {
        let details = ZenExtensionPermissions.hostAccess(patterns).map { [$0] } ?? []
        Task {
            let allowed = await ZenExtensionPrompt.allow(title: Self.askTitle(context), details: details)
            if allowed { ZenExtensionGrants.allow(patterns: patterns, for: context.uniqueIdentifier) }
            completionHandler(allowed ? patterns : [], nil)
        }
    }

    private static func askTitle(_ context: WKWebExtensionContext) -> String {
        "Allow \(context.webExtension.displayName ?? "this extension")?"
    }
}

// MARK: - TabManagerDelegate

extension ZenWebExtensions: TabManagerDelegate {
    func tabManager(_ tabManager: TabManager, didAddTab tab: Tab, placeNextToParentTab: Bool, isRestoring: Bool) {
        guard !tab.isPrivate else { return }
        register(tab)
    }

    func tabManagerDidRestoreTabs(_ tabManager: TabManager) {
        registerExistingTabs()
    }

    func tabManager(_ tabManager: TabManager, didRemoveTab tab: Tab, isRestoring: Bool) {
        guard knownTabs.remove(ObjectIdentifier(tab)) != nil else { return }
        controller.didCloseTab(tab, windowIsClosing: false)
    }

    func tabManager(_ tabManager: TabManager,
                    didSelectedTabChange selectedTab: Tab,
                    previousTab: Tab?,
                    isRestoring: Bool) {
        guard !selectedTab.isPrivate else { return }
        register(selectedTab)
        controller.didActivateTab(selectedTab, previousActiveTab: previousTab)
    }
}

struct LoadFailure: Identifiable {
    var id: String { package }
    let package: String
    let message: String
}

enum ZenWebExtensionError: Error {
    case noWindow
}
