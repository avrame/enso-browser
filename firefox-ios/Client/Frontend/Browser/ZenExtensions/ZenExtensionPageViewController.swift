// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import UIKit
import WebKit

/// Shows a page belonging to an extension, such as its options page.
///
/// WebKit cancels a navigation to an extension's URL in any web view not
/// built from that extension context's own configuration, which is why this
/// is not an ordinary browser tab.
@MainActor
final class ZenExtensionPageViewController: UIViewController {
    private let url: URL
    private let title_: String
    private let configuration: WKWebViewConfiguration
    private var webView: WKWebView?

    init(url: URL, title: String, configuration: WKWebViewConfiguration) {
        self.url = url
        self.title_ = title
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = title_
        view.backgroundColor = .systemBackground

        let webView = WKWebView(frame: view.bounds, configuration: configuration)
        webView.autoresizingMask = [UIView.AutoresizingMask.flexibleWidth, .flexibleHeight]
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        view.addSubview(webView)
        self.webView = webView

        let done = UIAction { [weak self] _ in self?.dismiss(animated: true) }
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: done)
        webView.load(URLRequest(url: url))
    }

    /// Wraps the page in a navigation controller ready to present.
    static func present(url: URL, title: String, configuration: WKWebViewConfiguration) {
        guard let presenter = UIWindow.keyWindow?.rootViewController?.topmostPresented else { return }
        let page = ZenExtensionPageViewController(url: url, title: title, configuration: configuration)
        let navigation = UINavigationController(rootViewController: page)
        presenter.present(navigation, animated: true)
    }
}
