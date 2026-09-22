// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import SwiftUI
import UIKit

/// Extensions are a feature people came here for, not a debug tool, so this
/// sits in General rather than behind the five taps on the version number.
class ExtensionsSetting: Setting {
    override var accessoryView: UIImageView? {
        guard let theme else { return nil }
        return SettingDisclosureUtility.buildDisclosureIndicator(theme: theme)
    }

    override var accessibilityIdentifier: String? { return "Extensions.Setting" }

    override var status: NSAttributedString? {
        let count = ZenWebExtensions.shared.installedCount
        guard count > 0 else { return nil }
        return NSAttributedString(string: count == 1 ? "1 installed" : "\(count) installed")
    }

    override func onClick(_ navigationController: UINavigationController?) {
        let controller = UIHostingController(rootView: ZenExtensionsView())
        controller.title = "Extensions"
        navigationController?.pushViewController(controller, animated: true)
    }
}
