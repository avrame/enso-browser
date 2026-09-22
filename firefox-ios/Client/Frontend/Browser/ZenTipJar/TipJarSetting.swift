// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import SwiftUI
import UIKit

class TipJarSetting: Setting {
    override var title: NSAttributedString? {
        guard let theme else { return nil }
        return NSAttributedString(string: "Leave a Tip",
                                  attributes: [.foregroundColor: theme.colors.textPrimary])
    }

    override var accessibilityIdentifier: String? { return "TipJar.Setting" }

    override func onClick(_ navigationController: UINavigationController?) {
        let controller = UIHostingController(rootView: TipJarView())
        controller.title = "Leave a Tip"
        navigationController?.pushViewController(controller, animated: true)
    }
}
