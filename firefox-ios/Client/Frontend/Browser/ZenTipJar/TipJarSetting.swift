// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import SwiftUI
import UIKit

/// Sits in its own section rather than among the legal links at the bottom of
/// About, where nobody found it. One row with one line under it is as loud as
/// asking for money should get in a browser that promises not to nag.
class TipJarSetting: Setting {
    override var accessoryView: UIImageView? {
        guard let theme else { return nil }
        return SettingDisclosureUtility.buildDisclosureIndicator(theme: theme)
    }

    override var status: NSAttributedString? {
        return NSAttributedString(string: "Ensō is free. If it's useful, buy me a coffee!")
    }

    override var accessibilityIdentifier: String? { return "TipJar.Setting" }

    override func onClick(_ navigationController: UINavigationController?) {
        let controller = UIHostingController(rootView: TipJarView())
        controller.title = "Leave a Tip"
        navigationController?.pushViewController(controller, animated: true)
    }
}
