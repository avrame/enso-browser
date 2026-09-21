# Extensions on iOS

Web extensions run through `WKWebExtension` (iOS 18.4+, which is why the app
targets it). The code lives in `firefox-ios/Client/Frontend/Browser/ZenExtensions`.

| Piece | What it does |
| --- | --- |
| `ZenWebExtensions` | The shared `WKWebExtensionController`, the controller delegate, and tab lifecycle |
| `ZenExtensionStore` | Packages on disk (`Application Support/ZenExtensions`); the file name is the context's identifier |
| `ZenExtensionWindow` | The browser window as extensions see it |
| `Tab+ZenWebExtension` | `Tab` conforming to `WKWebExtensionTab` |
| `ZenExtensionActions` | The toolbar button's action: popup, badge, click |
| `ZenExtensionPageViewController` | An extension's own pages, such as its options page |
| `ZenExtensionPermissions` / `ZenExtensionPrompt` / `ZenExtensionGrants` | What an extension may do, asked for and remembered |
| `ZenExtensionsView` | The Zen Extensions screen (Settings, tap version 5×, Debug) |

Extensions run in normal tabs only; private tabs are invisible to them.

## Windows: one, not one per space

Extensions come from a desktop world where windows contain tabs, so a browser
with spaces has to decide what a space looks like to an extension. Zen's spaces
could each be a window, which would make `tabs.query({currentWindow: true})`
return one space's tabs.

**This browser presents a single window** holding every normal tab.

The reason is that spaces do not own tabs here yet. The tab list is flat: a tab
opened from a space's pinned entry is linked back to it (`PinnedTabLinks`), but
an ordinary new tab belongs to no space, and nothing in the UI groups, filters
or switches tabs by space. Reporting a window per space would describe a
structure the user cannot see or move between, and would leave most tabs in a
nowhere window — an extension would be reasoning about a browser that does not
exist.

This is worth revisiting **once spaces own tabs**: a current space that new tabs
join, a tab tray that filters by it, and tab→space stored with the tab. At that
point the mapping follows the browser instead of inventing a parallel one, and
`ZenExtensionWindow` becomes one window per space, with the focused window
following the current space.

## Known limits

- Manifest v2 extensions with a persistent background page are rejected by
  WebKit ("Invalid `persistent` manifest entry"). MV3 is the practical target.
- An extension's page cannot load in a browser tab: WebKit cancels navigation
  to an extension URL in any web view not built from that extension context's
  `webViewConfiguration`. Such pages are presented by
  `ZenExtensionPageViewController`.
- Granting permissions only takes effect after `WKWebExtensionController.load`,
  and WebKit does not persist grants between launches — `ZenExtensionGrants`
  remembers what the user allowed and re-applies it.
- Installing is all-or-nothing: an extension gets everything its manifest asks
  for, or is not installed. Most extensions do not work partially granted, and
  Safari and Firefox prompt the same way.
