// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import SwiftUI
import UIKit

class ZenExtensionsDebugSetting: HiddenSetting {
    override var title: NSAttributedString? {
        guard let theme else { return NSAttributedString(string: "Zen Extensions") }
        return NSAttributedString(string: "Zen Extensions",
                                  attributes: [.foregroundColor: theme.colors.textPrimary])
    }

    override var accessibilityIdentifier: String? { return "ZenExtensionsDebug.Setting" }

    override func onClick(_ navigationController: UINavigationController?) {
        let controller = UIHostingController(rootView: ZenExtensionsView())
        controller.title = "Zen Extensions"
        navigationController?.pushViewController(controller, animated: true)
    }
}
