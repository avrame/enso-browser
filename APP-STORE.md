# App Store listing

Draft copy and the answers App Store Connect asks for. Character limits are
Apple's; the counts in brackets are what the text below actually uses.

## Name and subtitle

**App Name** (30 max) — `Ensō Browser` [12]

The bare name `Ensō` is contested: at least one app already ships under it, and
a search for "enso" returns fifteen meditation and wellness apps. `Ensō
Browser` says what it is and does not fight them for the word. The icon and the
name inside the app stay `Ensō`.

**Subtitle** (30 max) — `Zen spaces. Real extensions.` [28]

## Promotional text (170 max)

> Your Zen Browser spaces, on your phone — the same tabs, folders and split
> views, synced through your Mozilla account. Plus real extensions, including
> uBlock Origin. [162]

Promotional text can be changed without submitting a new build, so it is the
right place for anything that moves.

## Description

> Ensō puts your Zen Browser spaces on your phone.
>
> If you use Zen on the desktop, your spaces already hold the shape of your
> work — tabs grouped, folders nested, the split views you set up. Ensō reads
> them from the same Mozilla account Zen syncs with, so the phone opens on what
> you left rather than a wall of unsorted tabs.
>
> It also runs real browser extensions. Not content blockers with a fixed list,
> but actual WebExtensions you install from a file — uBlock Origin Lite among
> them — with their toolbar buttons, popups and options pages working the way
> they do everywhere else.
>
> AND IT IS QUIET
>
> Ensō collects nothing. No analytics, no telemetry, no crash reporting. It
> does not count its users or measure which features they use. There are no
> sponsored shortcuts on the homepage and no sponsored suggestions in the
> address bar, because that money would not be ours to take.
>
> Tracking protection is on by default, and blocks the companies that follow
> you from site to site.
>
> WHAT IT IS BUILT ON
>
> Ensō is built on Firefox for iOS, which Mozilla publishes as open source. The
> engine, the tracking protection and the sync all come from that work. Ensō is
> an independent project: it is not made by, endorsed by or affiliated with
> Mozilla, and it is not Firefox. It is likewise not affiliated with Zen
> Browser — it reads the spaces format Zen syncs, and that is the whole of the
> relationship.
>
> FREE, AND STAYING FREE
>
> There is nothing to unlock and no subscription. If you want to support the
> work there is a tip jar in Settings, and nothing in the browser changes
> whether you use it or not.
>
> Source: github.com/avrame/enso-browser

## Keywords (100 max)

> `spaces,tabs,sync,extensions,adblock,ad blocker,privacy,no ads,tracking,browser,web browser,tab group` [100]

**Do not put `firefox`, `zen browser`, `ublock` or `mozilla` in the keyword
field.** Apple's metadata rules forbid trademarked terms you do not own, and
competitor names in keywords are a common cause of rejection. Naming them
factually in the description is a different matter and is what the copy above
does.

## App Review answers

| Field | Value |
| --- | --- |
| Primary category | Utilities (where Safari's competitors live) |
| Secondary category | Productivity |
| Price | Free, with non-consumable tips |
| Support URL | https://github.com/avrame/enso-browser/issues |
| Marketing URL | *(optional — leave blank until there is a site)* |
| Privacy Policy URL | https://avrame.github.io/enso-browser/privacy.html |

**Age rating.** The questionnaire asks about unrestricted web access. A browser
must answer yes, which forces the highest bracket — the same one Chrome and
Firefox carry. There is no way around it and no reason to want one.

**iPhone only.** The Enso configuration sets `TARGETED_DEVICE_FAMILY = 1`, so
Apple reviews it on iPhone and asks for no iPad screenshots. The spaces sheet
and the toolbar were built for a phone and have never been looked at on a
tablet; claiming iPad would have meant shipping a stretched phone layout into
review. Adding iPad back is a piece of design work, not a build setting.

## App privacy — needs a decision, not a guess

The instinct is to answer **Data Not Collected**, and for Ensō itself that is
true: no analytics, no telemetry, no crash reporting, no servers of ours.

But Apple's label covers data collected through the app by third parties it
integrates, and signing in to sync sends browsing history, bookmarks, passwords
and open tabs to **Mozilla**. It is encrypted, it is optional, and Mozilla holds
it under their own notice — none of which is the same as it not happening.

Answering "Data Not Collected" while shipping a sync feature is the kind of
thing that gets a label challenged, and it would contradict the privacy notice
we wrote, which says plainly that Mozilla holds that data. The defensible
answer is to disclose the sync data as optional and used for app functionality.
Worth reading Apple's current guidance before filling the form in.

## Blockers

1. **Tip jar products.** The three consumables must exist in App Store Connect
   under the ids in `TipJar.productIDs` or the screen shows its unreachable
   state.
2. **The app privacy answer** above, which needs deciding rather than
   defaulting.

Done: the repository is `avrame/enso-browser` and `SupportUtils.URLForGetHelp`
follows it; the legal documents carry a real contact; and the privacy notice is
published at the URL in the table above, with `enso-guard.py` keeping the
hosted copy identical to the one the app ships.

## Signing, and what it took

Automatic signing needs every App ID to exist before Xcode will stop falling
back to the team's wildcard profile. A wildcard App ID cannot carry App
Groups, Push or AutoFill, so the errors it produces name the capabilities
rather than the real problem, which is the missing identifier.

Registered at developer.apple.com (Certificates, Identifiers & Profiles - a
different site from App Store Connect, which is the confusing part):

| Identifier | Capabilities |
| --- | --- |
| `app.enso.browser` | App Groups, AutoFill Credential Provider |
| `app.enso.browser.CredentialProvider` | App Groups, AutoFill Credential Provider |
| `app.enso.browser.ActionExtension` | App Groups |
| `app.enso.browser.NotificationService` | App Groups |
| `app.enso.browser.ShareTo` | App Groups |
| `app.enso.browser.WidgetKit` | App Groups |
| `app.enso.browser.Sticker` | none |
| `group.app.enso.browser` | the App Group itself |

Three things cost an afternoon between them:

- **Do not pin `CODE_SIGN_IDENTITY`.** Automatic signing picks Apple
  Development to build and Apple Distribution to archive. Pinning it to
  Development made Xcode hunt for a development profile while archiving.
- **Push was not worth its trouble.** It blocked provisioning, and it only
  buys receiving a sent tab. See `EnsoPush`.
- **Clean Build Folder does not refresh profiles.** Xcode Settings →
  Accounts → Download Manual Profiles does.

## Screenshots

Five are taken, at 1320 × 2868 — Apple's 6.9" iPhone size — in
`screenshots/app-store/`, with a README covering what each one shows and how
to retake it.

Still missing: **iPad**, which the target commits us to. See the note above.
