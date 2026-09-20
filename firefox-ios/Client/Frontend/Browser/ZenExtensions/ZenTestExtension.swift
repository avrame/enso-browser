// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

/// A tiny MV3 extension written to disk on demand, so the extension
/// pipeline (content script, background worker, `tabs` API) can be
/// exercised without installing anything. Developer builds only.
enum ZenTestExtension {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["ZEN_EXTENSIONS_TEST"] == "1"
    }

    private static let manifest = """
    {
      "manifest_version": 3,
      "name": "Zen Test Extension",
      "version": "1.0",
      "description": "Shows a banner on every page and counts open tabs.",
      "permissions": ["tabs"],
      "host_permissions": ["<all_urls>"],
      "background": { "service_worker": "background.js" },
      "content_scripts": [
        { "matches": ["<all_urls>"], "js": ["content.js"], "run_at": "document_idle" }
      ]
    }
    """

    private static let background = """
    browser.runtime.onMessage.addListener(async (message) => {
      if (message !== "tabCount") return undefined;
      const tabs = await browser.tabs.query({});
      return tabs.length;
    });
    """

    private static let content = """
    (async () => {
      const banner = document.createElement("div");
      banner.textContent = "Zen extension active";
      banner.style.cssText = [
        "position:fixed", "top:0", "left:0", "right:0", "z-index:2147483647",
        "background:#7542e4", "color:#fff", "font:600 14px -apple-system,sans-serif",
        "padding:8px", "text-align:center",
      ].join(";");
      document.documentElement.appendChild(banner);
      try {
        const count = await browser.runtime.sendMessage("tabCount");
        banner.textContent = `Zen extension active - ${count} tab(s)`;
      } catch (error) {
        banner.textContent = `Zen extension active - no background (${error})`;
      }
    })();
    """

    /// Writes the extension into Application Support and returns its directory.
    static func write() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
                                                  in: .userDomainMask,
                                                  appropriateFor: nil,
                                                  create: true)
        let directory = support.appendingPathComponent("ZenTestExtension/zen-test", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, contents) in [("manifest.json", manifest), ("background.js", background), ("content.js", content)] {
            try Data(contents.utf8).write(to: directory.appendingPathComponent(name))
        }
        return directory
    }
}
