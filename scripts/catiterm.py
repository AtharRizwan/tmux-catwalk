#!/usr/bin/env python3
# catiterm.py - print the active iTerm2 profile's background as #rrggbb.
#
# The sixel path needs a real colour to paint under the cat, and iTerm2 keeps
# the profile's background in its plist the same way Konsole keeps it in a
# .colorscheme. Reading it beats falling through to COLORFGBG, whose ANSI index
# is 0 for every dark theme and would put a pure black slab on a #15191f pane.
#
# Profile choice mirrors what the pane is actually using: $ITERM_PROFILE, which
# iTerm2 exports, else the default bookmark. Exit 1 and say nothing when the
# plist cannot be read, so the caller falls through to its next source.

import os
import plistlib
import subprocess
import sys

PLIST = "~/Library/Preferences/com.googlecode.iterm2.plist"


def main():
    try:
        raw = subprocess.run(
            ["plutil", "-convert", "xml1", "-o", "-", os.path.expanduser(PLIST)],
            capture_output=True, timeout=5).stdout
        prefs = plistlib.loads(raw)
    except Exception:
        return 1

    profiles = prefs.get("New Bookmarks") or []
    want = os.environ.get("ITERM_PROFILE", "")
    profile = next((p for p in profiles if want and p.get("Name") == want), None)
    if profile is None:
        guid = prefs.get("Default Bookmark Guid")
        profile = next((p for p in profiles if p.get("Guid") == guid), None)
    if profile is None:
        return 1

    keys = ["Background Color"]
    if profile.get("Use Separate Colors for Light and Dark Mode"):
        dark = os.environ.get("CATWALK_APPEARANCE") == "Dark"
        keys.insert(0, "Background Color (Dark)" if dark else "Background Color (Light)")

    for key in keys:
        colour = profile.get(key)
        if isinstance(colour, dict) and "Red Component" in colour:
            try:
                print("#%02x%02x%02x" % tuple(
                    min(255, max(0, round(colour[c] * 255)))
                    for c in ("Red Component", "Green Component", "Blue Component")))
            except (TypeError, ValueError):
                return 1
            return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
