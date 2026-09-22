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
> but actual WebExtensions installed from a file — uBlock Origin Lite included
> — with their toolbar buttons, popups and options pages working the way they
> do everywhere else.
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
| Privacy Policy URL | **blocked, see below** |

**Age rating.** The questionnaire asks about unrestricted web access. A browser
must answer yes, which forces the highest bracket — the same one Chrome and
Firefox carry. There is no way around it and no reason to want one.

**iPad.** The app builds for iPhone and iPad (`TARGETED_DEVICE_FAMILY = 1,2`),
so Apple will review it on iPad and require iPad screenshots. If the iPad
layout has not been looked at, either look at it or drop iPad from the target
before submitting.

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

1. **Privacy Policy URL.** App Store Connect requires a publicly reachable URL.
   Ours is bundled in the app at `enso://about/privacy` and nowhere else. It
   needs hosting — GitHub Pages off this repo is enough.
2. **Contact address.** `Terms.html` and `Privacy.html` both still say
   `[YOUR CONTACT ADDRESS]`. Shipping legal documents with a placeholder in
   them is worse than having none.
3. **Tip jar products.** The three consumables must exist in App Store Connect
   under the ids in `TipJar.productIDs` or the screen shows its unreachable
   state.
4. **Repo name.** Support and source links point at `avrame/firefox-ios`. For a
   browser whose listing carefully says it is not Firefox, a support link to a
   repo called firefox-ios undercuts the point. Rename it to `enso-browser` and
   update `SupportUtils.URLForGetHelp`.
5. **Screenshots.** None exist yet. See below.

## Screenshots

Required: 6.9" iPhone, plus iPad if iPad stays in the target. The simulator we
have (`Enso iOS 27`) is an iPhone 17 and is *not* one of the accepted sizes —
an iPhone 17 Pro Max simulator is.

Worth showing, in order:

1. The spaces sheet with real spaces in it — the one thing no other iOS browser
   can show. Needs a signed-in account with spaces.
2. A page with uBlock Origin's popup open and the toolbar badge showing.
3. The extensions list with an extension installed.
4. The homepage, showing no sponsored tile.
5. Settings, showing the absent telemetry switches.

The first two carry the listing. The rest are support.
