#!/usr/bin/env bash
# catwalk.tmux - tmux-catwalk entry point (run by tpm as an executable).
# Sets option defaults, installs hooks, binds the toggle key and does a
# catch-up pass for already-existing windows. Safe to re-run on reload.

set -uo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$CURRENT_DIR/scripts"
# shellcheck source=scripts/helpers.sh
. "$SCRIPTS/helpers.sh"

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
# A range rather than one number, so the pool walks at a spread of gaits instead
# of in lockstep. The old default of a flat `1` was ten columns a second, which
# crosses a wide pane in under twenty seconds and reads as hurrying rather than
# strolling; every critter is slower than that now, and no two quite alike.
default catwalk-step 0.4-0.8
# ltr, rtl, or random. random, the default, draws a direction per critter and
# mirrors the artwork of the ones walking against the way they were drawn - a
# strip where everyone files past the same way reads as a conveyor belt rather
# than as animals. `ltr` or `rtl` pins one direction for the whole pool, which
# also halves the render: only the one flip of each GIF can ever occur, so only
# that one is built.
default catwalk-direction random
# A single GIF walks end to end for ever, exactly as it always has. A directory
# turns on the spawner: critters appear at random, one at a time or three at
# once, each with its own GIF, speed and direction.
default catwalk-gif ""
# Which way the artwork itself walks, so the spawner knows who to mirror. A file
# named `fox.ltr.gif` says so for itself and overrides this.
default catwalk-facing rtl
default catwalk-mirror 1
# Spawner shape: how many critters to keep walking at once, how often one is
# born (auto = as often as @catwalk-max-cats needs), how bunched up the arrivals
# are, and a cap on how many GIFs to take out of a large directory.
default catwalk-max-cats 2
default catwalk-spawn auto
default catwalk-density 70
default catwalk-max-gifs 0
default catwalk-bind C
default catwalk-cache-dir "${XDG_CACHE_HOME:-$HOME/.cache}/tmux-catwalk"
default catwalk-sixel-check 1
# Background painted under the GIF's transparent pixels on the sixel path.
# Empty, the default, means "whatever suits this terminal": a real alpha channel
# where the terminal can do it, and otherwise the terminal's own background
# colour auto-detected (Konsole color scheme, else $COLORFGBG) and painted in.
# A hex like #1e1e2e pins an opaque colour and keeps the sixel path; the literal
# `transparent` asks for the alpha channel outright.
default catwalk-bg ""
# Which graphics protocol to draw with: auto, sixel or kitty. auto takes the
# kitty path on any terminal known to implement it - that is where transparency
# comes from, and it no longer has to be opted into with @catwalk-bg - and falls
# back to sixel on terminals that would print the escapes as garbage.
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

# Switching *sessions* is the same problem one level up, and worse: a cat can
# only erase through a client attached to its own session, so the session being
# left keeps no way to take its last frame off the terminal - the arriving
# session's cat has to sweep it up (see kitty_clear). Without this hook that
# happens on the next two-second sweep, which is two seconds of the previous
# session's cats sitting on top of the one you just switched to.
tmux set-hook -g 'client-session-changed[99]' "run-shell '$SCRIPTS/catpoke'"

# A kitty cat uploads its frames to the terminal once, through passthrough, and
# passthrough reaches a terminal only while a client is attached to the session.
# Attaching, detaching, or reattaching from another terminal window therefore
# changes - or removes - the only place those frames exist, and the cats have to
# upload again. catpoke is the same nudge the zoom hook uses; the cats work out
# for themselves whether the audience actually changed.
tmux set-hook -g 'client-attached[99]' "run-shell '$SCRIPTS/catpoke'"
tmux set-hook -g 'client-detached[99]' "run-shell '$SCRIPTS/catpoke'"

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
#
# At boot this runs *before* tmux-continuum's restore, which arms itself here
# and only then sleeps a second, so the pgrep-for-restore.sh guard inside
# catensure-all sees nothing and would happily spawn. It must not: the cat lands
# beside the shell the user's own `tmux new -As foo` just made, resurrect counts
# two panes instead of one, stops treating the server as empty, and merges the
# saved windows into the existing one - a pane short, and with a pane count the
# saved layout string no longer matches, so select-layout fails and the window
# is left as a flat stack of full-width panes. catrestore_pending in helpers.sh
# is the check; catlater does the pass once the restore is over.
if tmux list-sessions >/dev/null 2>&1; then
    if catrestore_running || catrestore_pending; then
        tmux run-shell -b "$SCRIPTS/catlater" 2>/dev/null
    else
        tmux run-shell "$SCRIPTS/catensure-all" 2>/dev/null
    fi
fi
