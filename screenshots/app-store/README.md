# App Store screenshots

1320 × 2868 — Apple's 6.9" iPhone size. Captured on an iPhone 18 Pro Max
simulator running iOS 27, in light mode with the address bar at the bottom,
which are the defaults rather than anyone's customised setup.

| File | What it shows |
| --- | --- |
| `01-spaces.png` | A real Zen space with its folders nested and the space switcher |
| `02-extension-popup.png` | uBlock Origin Lite's own popup, open on a news site |
| `03-extensions.png` | The extensions list, with what the installed one was allowed to do |
| `04-homepage.png` | The homepage, with no sponsored shortcut in the row |
| `05-settings.png` | Extensions and the tip jar in Settings, and no telemetry switches |

The first two carry the listing: they are the two things no other iOS browser
does. The rest are support.

## Retaking one

The panel's screenshot button fails intermittently. This does not:

```bash
xcrun simctl io <device-udid> screenshot 01-spaces.png
```

`01` needs a signed-in account with spaces in it, and a folder expanded —
which writes the expansion back to the real Zen account, so collapse it
afterwards if it matters. `02` needs an extension installed and a page with
something worth blocking; a site with nothing to block shows no badge, which
is correct and makes a poor screenshot.
