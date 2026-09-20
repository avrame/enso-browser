// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import UIKit
import WebKit

/// The toolbar button's side of an extension's action: what to show, and
/// what happens when it is tapped.
@MainActor
enum ZenExtensionActions {
    struct Item: Identifiable {
        let context: WKWebExtensionContext
        let action: WKWebExtension.Action

        var id: String { context.uniqueIdentifier }
        var title: String {
            let label = action.label
            return label.isEmpty ? (context.webExtension.displayName ?? id) : label
        }
        var badge: String { action.badgeText }
    }

    /// One item per loaded extension, for the tab the user is looking at.
    static func items(for tab: Tab?) -> [Item] {
        ZenWebExtensions.shared.contexts.compactMap { context in
            guard let action = context.action(for: tab) else { return nil }
            return Item(context: context, action: action)
        }
    }

    /// Opens the extension's popup, or fires its click handler when it has
    /// no popup to show.
    static func run(_ item: Item, from sourceView: UIView?) {
        guard item.action.presentsPopup else {
            item.context.performAction(for: item.action.associatedTab)
            return
        }
        present(item.action, from: sourceView)
    }

    static func present(_ action: WKWebExtension.Action, from sourceView: UIView?) {
        guard let controller = action.popupViewController,
              let presenter = UIWindow.keyWindow?.rootViewController?.topmostPresented,
              controller.presentingViewController == nil
        else { return }

        if let popover = controller.popoverPresentationController, let sourceView {
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
        }
        controller.sheetPresentationController?.detents = [.medium(), .large()]
        controller.sheetPresentationController?.prefersGrabberVisible = true
        presenter.present(controller, animated: true)
    }
}
