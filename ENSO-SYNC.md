# Syncing from firefox-ios

Ensō tracks Mozilla's `firefox-ios`. Most of our work sits in files upstream
does not have, and merges cleanly. Two things do not, and both fail quietly:
the browser keeps running and says something untrue.

## The two quiet ones

**Localised strings we replaced.** Mozilla's l10n imports rewrite whole
`.strings` files. Where we replaced their copy — the non-profit claims, the
Suggest titles — an import can put theirs back, in any of 143 files. Nothing
conflicts, because upstream changed the file and we are merging their version
of it.

**The advertised Firefox version.** `UserAgent.firefoxCompatVersion` is what
sites are told the engine is. It cannot follow `APP_VERSION`, because that is
Ensō's own version now (0.1.0), and sites gate features on the FxiOS number.
So it is pinned by hand, and a pin nobody notices going stale tells sites the
wrong engine is running.

`scripts/enso-guard.py` catches both. It runs from the pre-push hook, so a
sync cannot reach the remote having undone either one.

## Doing a sync

```bash
git fetch upstream
git checkout -b sync-upstream-$(date +%F)
git merge upstream/main
```

Then, before trusting it:

1. `python3 scripts/enso-guard.py` — names any string upstream took back, and
   whether the advertised Firefox version is now behind.
2. `python3 scripts/enso-guard.py --update` — after a sync this is usually the
   right answer for the version: the engine really is the newer one, so
   following it is honest. It is *not* the right answer for a string the
   import reverted; restore our wording first, then update the lock.
3. Build, then run the app and check the things that have broken before:
   signing in to a Mozilla account, opening Spaces, installing an extension
   from a `.xpi` and opening its popup.

The guard only knows about strings we have already overridden. If you change
another one, run `--update` so it is locked from then on.

## What the lock file is

`scripts/enso-strings.lock` records a hash of every string value we override,
derived from `git diff upstream/main HEAD`. It is generated, not hand-kept —
`--update` rewrites it. A changed hash means an import rewrote something we
had deliberately changed.
