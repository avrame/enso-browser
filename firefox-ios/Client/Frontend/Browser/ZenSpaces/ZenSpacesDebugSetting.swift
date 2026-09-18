// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import SwiftUI
import UIKit

class ZenSpacesDebugSetting: HiddenSetting {
    override var title: NSAttributedString? {
        guard let theme else { return NSAttributedString(string: "Zen Spaces (read-only)") }
        return NSAttributedString(string: "Zen Spaces (read-only)",
                                  attributes: [.foregroundColor: theme.colors.textPrimary])
    }

    override var accessibilityIdentifier: String? { return "ZenSpacesDebug.Setting" }

    override func onClick(_ navigationController: UINavigationController?) {
        let accountManager = settings.profile?.rustFxA.accountManager
        let view = ZenSpacesDebugView(loadAuth: {
            try await ZenSpacesAuthProvider(accountManager: accountManager).auth()
        })
        let controller = UIHostingController(rootView: view)
        controller.title = "Zen Spaces"
        navigationController?.pushViewController(controller, animated: true)
    }
}
