// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

extension ToolbarActionConfiguration {
    /// Sits next to the Spaces button, and only while something is installed.
    @MainActor
    static var zenExtensions: ToolbarActionConfiguration {
        ToolbarActionConfiguration(
            actionType: .extensions,
            iconName: "puzzlepiece.extension",
            badgeText: ZenWebExtensions.shared.toolbarBadge,
            isEnabled: true,
            a11yLabel: "Extensions",
            a11yId: AccessibilityIdentifiers.Toolbar.extensionsButton)
    }
}
