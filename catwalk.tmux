#!/usr/bin/env bash
# catwalk.tmux - tmux-catwalk entry point (run by tpm as an executable).
# Sets option defaults, installs hooks, binds the toggle key and does a
# catch-up pass for already-existing windows. Safe to re-run on reload.

set -uo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$CURRENT_DIR/scripts"

# default <name-without-@> <value> - set only if unset
default() {
    if ! tmux show-options -gv "@$1" >/dev/null 2>&1; then
        tmux set-option -g "@$1" "$2"
    fi
}

default cats-on 1
default catwalk-height 3
default catwalk-cell-ratio 2.4
default catwalk-fps 10
default catwalk-step 1
default catwalk-direction rtl
default catwalk-gif ""
default catwalk-bind C
default catwalk-cache-dir "${XDG_CACHE_HOME:-$HOME/.cache}/tmux-catwalk"
default catwalk-sixel-check 1
# Background for the GIF's transparent pixels (sixel has no alpha). Empty =
# auto-detect the terminal's background color (Konsole); set a hex like
# #1e1e2e to override.
default catwalk-bg ""

# Cats appear in the initial window of a fresh session (session-created) and
# in every subsequent new window. The after-* hooks run a catch-up scan: the
# hooks cannot tell us which window was created (run-shell's TMUX_PANE points
# at the session's current pane, not the new window), so we just ensure a cat
# in every window - dedup in catensure makes it idempotent and cheap.
tmux set-hook -g session-created "run-shell '$SCRIPTS/catensure-all'"
tmux set-hook -g after-new-window "run-shell '$SCRIPTS/catensure-all'"

# Catch-up after a resurrect restore (deferred spawns land here), unless the
# user defined their own hook.
if ! tmux show-options -gv @resurrect-hook-post-restore-all >/dev/null 2>&1; then
    tmux set-option -g @resurrect-hook-post-restore-all \
        "tmux run-shell '$SCRIPTS/catensure-all --restored'"
fi

BIND="$(tmux show-options -gv @catwalk-bind 2>/dev/null || echo C)"
tmux bind-key "$BIND" run-shell "$SCRIPTS/cattoggle"

# Catch-up on a running server (reload / tpm install / prefix + I).
if tmux list-sessions >/dev/null 2>&1; then
    tmux run-shell "$SCRIPTS/catensure-all" 2>/dev/null
fi
