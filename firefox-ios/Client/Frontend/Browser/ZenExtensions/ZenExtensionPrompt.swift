// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import UIKit

/// Asks the user to allow something an extension requested while running.
@MainActor
enum ZenExtensionPrompt {
    static func allow(title: String, details: [String]) async -> Bool {
        guard let presenter = UIWindow.keyWindow?.rootViewController?.topmostPresented else { return false }
        let message = details.isEmpty ? nil : details.map { "• \($0)" }.joined(separator: "\n")

        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Don’t Allow", style: .cancel) { _ in
                continuation.resume(returning: false)
            })
            alert.addAction(UIAlertAction(title: "Allow", style: .default) { _ in
                continuation.resume(returning: true)
            })
            presenter.present(alert, animated: true)
        }
    }
}

extension UIViewController {
    var topmostPresented: UIViewController {
        presentedViewController?.topmostPresented ?? self
    }
}
