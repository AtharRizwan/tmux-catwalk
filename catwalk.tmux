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

# Cell geometry used to be baked in as 11x26 / 2.4, which is only right for the
# terminal it was measured on -- and, worse, only right for the windows tmux
# happens to agree with: it measures a sixel in cells using the window's own
# xpixel/ypixel, and a window that has never been resized keeps tmux's 16x32
# default forever, drawing the cat a fifth too narrow. Both are detected at
# render time now. Take back the two values this plugin itself wrote, once per
# server, so an existing session picks up the fix without being unset by hand.
if [[ "$(tmux show-options -gv @catwalk-cell-auto 2>/dev/null)" != "1" ]]; then
    [[ "$(tmux show-options -gv @catwalk-cell-px 2>/dev/null)" == "11x26" ]] &&
        tmux set-option -g @catwalk-cell-px auto
    [[ "$(tmux show-options -gv @catwalk-cell-ratio 2>/dev/null)" == "2.4" ]] &&
        tmux set-option -g @catwalk-cell-ratio auto
    tmux set-option -g @catwalk-cell-auto 1
fi

default cats-on 1
default catwalk-height 3
default catwalk-cell-ratio auto
default catwalk-cell-px auto
default catwalk-top-pad 1
default catwalk-fps 10
default catwalk-step 1
default catwalk-direction rtl
default catwalk-gif ""
default catwalk-bind C
default catwalk-cache-dir "${XDG_CACHE_HOME:-$HOME/.cache}/tmux-catwalk"
default catwalk-sixel-check 1
# Background painted under the GIF's transparent pixels on the sixel path.
# Empty = auto-detect the terminal's background color (Konsole color scheme,
# else $COLORFGBG); a hex like #1e1e2e overrides it. The literal `transparent`
# asks for a real alpha channel instead, via the Kitty graphics path.
default catwalk-bg ""
# Which graphics protocol to draw with: auto, sixel or kitty. auto uses kitty
# only when @catwalk-bg is transparent and the terminal is known to support it.
default catwalk-graphics auto

# Cats appear in the initial window of a fresh session (session-created) and
# in every subsequent new window. The after-* hooks run a catch-up scan: the
# hooks cannot tell us which window was created (run-shell's TMUX_PANE points
# at the session's current pane, not the new window), so we just ensure a cat
# in every window - dedup in catensure makes it idempotent and cheap.
#
# A plugin-specific hook index is used rather than the default [0]: a plain
# `set-hook -g session-created` overwrites index 0 and would silently destroy
# whatever another plugin (or the user) installed there. Writing to a fixed
# high index leaves the other slots alone and stays idempotent across reloads,
# which `set-hook -a` would not (it appends a duplicate every time).
#
# Earlier versions did write to index 0. Take that entry back if - and only if -
# it is still one of ours, so upgrading does not leave the catch-up pass wired
# up twice, while a hook someone else owns is left untouched.
unhook_ours() {
    local ev cur
    ev="$1"
    cur="$(tmux show-hooks -g 2>/dev/null | awk -v e="$ev[0]" '$1==e {$1=""; sub(/^ /,""); print}')"
    if [[ "$cur" == *"$SCRIPTS/catensure-all"* ]]; then
        tmux set-hook -gu "$ev[0]" 2>/dev/null
    fi
}
unhook_ours session-created
unhook_ours after-new-window

tmux set-hook -g 'session-created[99]' "run-shell '$SCRIPTS/catensure-all'"
tmux set-hook -g 'after-new-window[99]' "run-shell '$SCRIPTS/catensure-all'"

# Zooming a pane hides every other pane without resizing it, so a cat gets no
# SIGWINCH and would leave its last frame sitting on the terminal. This fires on
# zoom, unzoom and `choose-tree -Z` alike (verified), and catpoke nudges the cats
# to re-check what is actually on screen.
tmux set-hook -g 'window-layout-changed[99]' "run-shell '$SCRIPTS/catpoke'"

# Switching windows changes no layout, so the hook above never fires for it. The
# sixel path does not care - tmux draws only the current window - but a kitty
# cat draws through passthrough, which tmux forwards from every window of the
# session, so each cat has to know whether its own window is the one on screen.
# Without this it would find out on its next two-second sweep, and the incoming
# window would be catless until then.
tmux set-hook -g 'session-window-changed[99]' "run-shell '$SCRIPTS/catpoke'"

# tmux-resurrect brings panes back as plain shells - it does not re-run
# arbitrary pane commands - so a cat that was present at save time returns as an
# empty strip, and the catch-up pass would add a real cat beside it: one more
# dead strip per window per restore. catsave records where the cats were and the
# post-restore pass respawns those exact panes. Both hooks yield to a
# user-defined one.
# post-save-layout is handed the state file and fires before resurrect
# finalises it. The hook is eval'd by resurrect with that path appended, so it
# points straight at the script rather than going through run-shell.
if ! tmux show-options -gv @resurrect-hook-post-save-layout >/dev/null 2>&1; then
    tmux set-option -g @resurrect-hook-post-save-layout "$SCRIPTS/catsave"
fi
if ! tmux show-options -gv @resurrect-hook-post-restore-all >/dev/null 2>&1; then
    tmux set-option -g @resurrect-hook-post-restore-all \
        "tmux run-shell '$SCRIPTS/catensure-all --restored'"
fi

# Rebinding leaves the previously bound key live unless we take it back first.
PREV_BIND="$(tmux show-options -gv @catwalk-bound-key 2>/dev/null || true)"
BIND="$(tmux show-options -gv @catwalk-bind 2>/dev/null || echo C)"
if [[ -n "$PREV_BIND" && "$PREV_BIND" != "$BIND" ]]; then
    tmux unbind-key "$PREV_BIND" 2>/dev/null
fi
if [[ -n "$BIND" ]]; then
    tmux bind-key "$BIND" run-shell "$SCRIPTS/cattoggle"
    tmux set-option -g @catwalk-bound-key "$BIND"
fi

# Catch-up on a running server (reload / tpm install / prefix + I).
if tmux list-sessions >/dev/null 2>&1; then
    tmux run-shell "$SCRIPTS/catensure-all" 2>/dev/null
fi
