// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

extension ToolbarActionConfiguration {
    /// Shown in the navigation toolbar, or in the address bar when that
    /// toolbar is hidden (iPad, iPhone landscape).
    static let zenSpaces = ToolbarActionConfiguration(
        actionType: .spaces,
        iconName: "square.stack",
        isEnabled: true,
        a11yLabel: "Spaces",
        a11yId: AccessibilityIdentifiers.Toolbar.spacesButton)
}
