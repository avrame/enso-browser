#!/usr/bin/env python3
"""Guards the two Ensō changes that upstream can silently undo.

Both failures are quiet ones: nothing crashes, nothing looks wrong in a diff,
and the browser just starts telling people something untrue again.

  strings  Mozilla's localisation imports rewrite whole .strings files. Where
           we replaced their copy - the non-profit claims, the Suggest titles -
           an import can put theirs back. Only the values we deliberately
           overrode are locked; everything else is upstream's to change.

  version  The FxiOS version sites are told about is pinned in Swift, because
           it must not follow Ensō's own version. Upstream bumps the real one
           every release, and a pin nobody notices going stale is a lie about
           which engine is running.

Run with --update after intentionally rewording a locked string, or after a
sync that legitimately bumps the Firefox version.
"""
import hashlib
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LOCK = ROOT / "scripts" / "enso-strings.lock"
VERSION_XCCONFIG = ROOT / "firefox-ios/Client/Configuration/version.xcconfig"
USER_AGENT = ROOT / "BrowserKit/Sources/Shared/UserAgent.swift"
UPSTREAM = "upstream/main"
STRING_PATHS = ["firefox-ios/Shared/Supporting Files", "firefox-ios/Client"]

ENTRY = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;')


def strings_in(text):
    """Every key/value pair in a .strings file, by line."""
    pairs = {}
    for line in text.splitlines():
        match = ENTRY.match(line.strip())
        if match:
            pairs[match.group(1)] = match.group(2)
    return pairs


def digest(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:16]


def overridden_keys():
    """The (file, key) pairs where our copy differs from upstream's.

    Taken from the diff rather than a hand-kept list, so a string we change
    later is picked up by --update instead of being forgotten.
    """
    try:
        diff = subprocess.run(
            ["git", "diff", UPSTREAM, "HEAD", "--unified=0", "--"] + STRING_PATHS,
            cwd=ROOT, capture_output=True, text=True, check=True).stdout
    except subprocess.CalledProcessError:
        sys.exit(f"could not diff against {UPSTREAM}. Fetch it first: git fetch upstream")

    found, path = [], None
    for line in diff.splitlines():
        if line.startswith("+++ b/"):
            # git appends a tab when the path contains a space, which every
            # path under "Supporting Files" does.
            path = line[6:].rstrip("\t")
        elif line.startswith("+") and path and path.endswith(".strings"):
            match = ENTRY.match(line[1:].strip())
            if match:
                found.append((path, match.group(1)))
    return found


def update_version():
    """Point the advertised Firefox version at whatever upstream now is.

    After a sync the engine really is the newer one, so following it is the
    honest move - unlike Ensō's own version, which stays ours.
    """
    xcconfig = re.search(r"^APP_VERSION\s*=\s*(\S+)",
                         VERSION_XCCONFIG.read_text(encoding="utf-8"), re.M)
    if not xcconfig:
        return
    text = USER_AGENT.read_text(encoding="utf-8")
    updated = re.sub(r'(firefoxCompatVersion\s*=\s*")[^"]+(")',
                     rf"\g<1>{xcconfig.group(1)}\g<2>", text)
    if updated != text:
        USER_AGENT.write_text(updated, encoding="utf-8")
        print(f"advertised Firefox version is now {xcconfig.group(1)}")


def update():
    update_version()
    lines = []
    for path, key in sorted(set(overridden_keys())):
        file = ROOT / path
        if not file.exists():
            continue
        value = strings_in(file.read_text(encoding="utf-8")).get(key)
        if value is not None:
            lines.append(f"{path}\t{key}\t{digest(value)}")
    LOCK.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"locked {len(lines)} strings in {LOCK.relative_to(ROOT)}")


def check_strings():
    if not LOCK.exists():
        return [f"{LOCK.relative_to(ROOT)} is missing. Run scripts/enso-guard.py --update"]

    wanted = {}
    for line in LOCK.read_text(encoding="utf-8").splitlines():
        if line.strip():
            path, key, want = line.split("\t")
            wanted.setdefault(path, []).append((key, want))

    problems = []
    for path, entries in sorted(wanted.items()):
        file = ROOT / path
        if not file.exists():
            problems.append(f"{path}: file is gone, but {len(entries)} of our strings were in it")
            continue
        current = strings_in(file.read_text(encoding="utf-8"))
        for key, want in entries:
            value = current.get(key)
            if value is None:
                problems.append(f"{path}: our string {key} was removed")
            elif digest(value) != want:
                problems.append(f'{path}: {key} was rewritten to "{value[:60]}"')
    return problems


def check_version():
    xcconfig = re.search(r"^APP_VERSION\s*=\s*(\S+)",
                         VERSION_XCCONFIG.read_text(encoding="utf-8"), re.M)
    swift = re.search(r'firefoxCompatVersion\s*=\s*"([^"]+)"',
                      USER_AGENT.read_text(encoding="utf-8"))
    if not xcconfig or not swift:
        return ["could not read the Firefox version from version.xcconfig or UserAgent.swift"]
    if xcconfig.group(1) != swift.group(1):
        return [f"UserAgent.firefoxCompatVersion is {swift.group(1)}, "
                f"but upstream is now on {xcconfig.group(1)}. "
                f"Sites are being told the wrong engine version."]
    return []


def main():
    if "--update" in sys.argv:
        update()
        return 0

    problems = check_version() + check_strings()
    if problems:
        print("Ensō guard found changes upstream undid:\n", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        print("\nFix them, or run scripts/enso-guard.py --update if the change was "
              "intended.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
