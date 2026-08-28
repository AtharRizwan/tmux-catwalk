# shellcheck shell=bash
# helpers.sh - shared helpers for tmux-catwalk. Source this file.
# Resolve script/plugin dirs from this file's own location.
CATWALK_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATWALK_PLUGIN_DIR="$(dirname "$CATWALK_SCRIPT_DIR")"

# catopt <name-without-@> <default> - read a global tmux option (with default)
catopt() {
    local v
    v="$(tmux show-options -gv "@$1" 2>/dev/null)"
    printf '%s' "${v:-$2}"
}

# catcfg <ENVVAR> <name-without-@> <default> - env var wins, else option, else default
catcfg() {
    local envval="${!1:-}"
    if [[ -n "$envval" ]]; then
        printf '%s' "$envval"
    else
        catopt "$2" "$3"
    fi
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# cache dir shared by catwalk and the cache prune
catcache() {
    catcfg CATWALK_CACHE catwalk-cache-dir "${XDG_CACHE_HOME:-$HOME/.cache}/tmux-catwalk"
}

# catgif - the configured GIF *path*, with a leading ~ expanded. tmux does not
# expand a tilde inside a single-quoted option value and bash will not expand
# one that arrives via a variable, so a `~/...` path would otherwise never
# resolve. This may name a directory; catgifs is what turns it into a pool.
catgif() {
    local g
    g="$(catcfg CATWALK_GIF catwalk-gif '')"
    printf '%s' "${g/#\~/$HOME}"
}

# catgifs - every GIF in the pool, one path per line.
#
# @catwalk-gif may name a single file, as it always could, or a directory, in
# which case every .gif inside it joins the pool and the spawner draws from all
# of them. The listing is sorted because the spawner picks a critter by hashing
# a slot number into this array: an ordering that differed between panes would
# put a different animal in every window at the same instant, and the whole
# point of deriving everything from the clock is that they agree.
#
# Symlinks count (-xtype f resolves them), subdirectories deliberately do not.
catgifs() {
    local g
    g="$(catgif)"
    [[ -n "$g" ]] || return 0
    if [[ -d "$g" ]]; then
        find "$g" -maxdepth 1 -xtype f -iname '*.gif' -print 2>/dev/null | LC_ALL=C sort
    else
        printf '%s\n' "$g"
    fi
}

# catfacing <path> <default> - which way the artwork in this GIF walks, ltr or
# rtl. Sprites that travel against their artwork are mirrored, so this has to be
# known per file: one directory can easily hold critters drawn facing both ways,
# and a single global setting would leave half of them moonwalking. A filename
# may say so itself - `fox.ltr.gif` - and otherwise the pool default applies.
catfacing() {
    local base
    base="${1##*/}"
    case "${base,,}" in
        *.ltr.gif) printf 'ltr'; return 0 ;;
        *.rtl.gif) printf 'rtl'; return 0 ;;
    esac
    [[ "${2:-rtl}" == "ltr" ]] && printf 'ltr' || printf 'rtl'
}

# tmux measures a sixel in cells with the *window's* idea of a cell (input.c
# hands w->xpixel/w->ypixel to sixel_parse) and then repaints it with the
# *client's* (tty.c scales by tty->xpixel/tty->ypixel). The two need not agree:
# recalculate_size() only re-sizes a window when its character size changes and
# never looks at the pixel fields, so a window that has never been resized -- a
# session restored at the client's exact character size, typically -- keeps
# tmux's DEFAULT_XPIXEL/DEFAULT_YPIXEL (16x32) for good, and every image drawn
# in it is read at the wrong scale.

# catwincell <target> - the window's cell size as "WxH": the grid a sixel canvas
# has to land on. Empty when tmux cannot say.
catwincell() {
    local v
    v="$(tmux display -p -t "$1" '#{window_cell_width}x#{window_cell_height}' 2>/dev/null)"
    [[ "$v" =~ ^[0-9]+[xX][0-9]+$ ]] || return 0
    printf '%s' "$v"
}

# catclientcell <target> - the attached client's real cell size as "WxH". The
# sixel path uses it for the aspect ratio only, never for the canvas; the kitty
# path bakes to it, since there the terminal draws the pixmap itself and the
# window's idea of a cell never enters into it. Empty when nothing is attached.
catclientcell() {
    local v
    v="$(tmux display -p -t "$1" '#{client_cell_width}x#{client_cell_height}' 2>/dev/null)"
    [[ "$v" =~ ^[0-9]+[xX][0-9]+$ ]] || return 0
    printf '%s' "$v"
}

# catpanes - print the pane id of every live catwalk pane. Panes stamp
# themselves with the @catwalk pane option on startup; matching on that instead
# of on a substring of #{pane_start_command} means a pane that merely mentions
# "catwalk" (an editor open on this very file, say) is never mistaken for a cat.
catpanes() {
    tmux list-panes -a -f '#{@catwalk}' -F '#{pane_id}' 2>/dev/null
}

# catwin_has_cat <window-id> - true if that window already holds a cat pane
catwin_has_cat() {
    [[ -n "$(tmux list-panes -t "$1" -f '#{@catwalk}' -F '#{pane_id}' 2>/dev/null)" ]]
}

# catsixel_ok - does the client we would draw into understand sixel? Prefer the
# attached clients' resolved feature sets; fall back to the raw global option
# when nothing is attached (hooks can run without a client).
catsixel_ok() {
    local feats
    feats="$(tmux list-clients -F '#{client_termfeatures}' 2>/dev/null | tr '\n' ',')"
    if [[ -n "${feats//,/}" ]]; then
        [[ "$feats" == *sixel* ]]
    else
        tmux show-options -gv terminal-features 2>/dev/null | grep -q sixel
    fi
}

# catbg - best-effort opaque background for transparent pixels in the sixel
# path. Konsole renders a sixel into an indexed image whose unpainted pixels
# take colour register 0, opaque, so chafa has to paint those pixels *some*
# colour; matching the terminal's own background makes the box blend in instead
# of reading as a black (or blue) slab. Precedence: $CATWALK_BG / @catwalk-bg,
# else the active Konsole color scheme's [Background] Color, else $COLORFGBG's
# background index, else empty (chafa assumes black).
#
# The literal value `transparent` is a mode marker rather than a colour: it asks
# for the Kitty graphics path, which has a real alpha channel. It is returned
# untouched here and resolved by catmode.
catbg() {
    local v profile file r g b
    # Must be initialised: `local scheme` alone leaves it *unset*, and reading
    # an unset variable under `set -u` aborts the function - which is what used
    # to happen on every non-Konsole system.
    local scheme=""
    v="$(catcfg CATWALK_BG catwalk-bg '')"
    [[ -n "$v" ]] && { printf '%s' "$v"; return; }

    profile="$(awk -F= '/^DefaultProfile=/{print $2; exit}' "$HOME/.config/konsolerc" 2>/dev/null)"
    if [[ -n "$profile" && -f "$HOME/.local/share/konsole/$profile" ]]; then
        scheme="$(awk -F= '/^ColorScheme=/{print $2; exit}' "$HOME/.local/share/konsole/$profile")"
    fi
    if [[ -z "$scheme" ]]; then
        for file in "$HOME"/.local/share/konsole/*.profile; do
            [[ -f "$file" ]] || continue
            scheme="$(awk -F= '/^ColorScheme=/{print $2; exit}' "$file")"
            [[ -n "$scheme" ]] && break
        done
    fi

    if [[ -n "$scheme" ]]; then
        file="$HOME/.local/share/konsole/$scheme.colorscheme"
        [[ -f "$file" ]] || file="/usr/share/konsole/ColorSchemes/$scheme.colorscheme"
        if [[ -f "$file" ]]; then
            v="$(awk -F= '/^\[[^]]*\]/{sec=$0} sec=="[Background]" && $1=="Color"{print $2; exit}' "$file")"
            v="${v//[[:space:]]/}"
            IFS=, read -r r g b <<< "$v"
            if [[ "$r" =~ ^[0-9]+$ && "$g" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ ]]; then
                printf '#%02x%02x%02x' \
                    "$((r < 256 ? r : 255))" "$((g < 256 ? g : 255))" "$((b < 256 ? b : 255))"
                return 0
            fi
        fi
    fi

    catbg_colorfgbg
}

# catbg_colorfgbg - terminals that are not Konsole (xterm, foot, WezTerm, ...)
# commonly export COLORFGBG as "fg;bg" or "fg;default;bg", where bg is an ANSI
# palette index. Map that index through the standard xterm palette. Querying the
# terminal with OSC 11 is not an option here: catbg runs inside run-shell/command
# substitution, with no tty to read the reply from.
catbg_colorfgbg() {
    local bg
    [[ -n "${COLORFGBG:-}" ]] || return 0
    bg="${COLORFGBG##*;}"
    [[ "$bg" =~ ^[0-9]+$ ]] || return 0
    case "$bg" in
        0) printf '#000000' ;;  1) printf '#800000' ;;  2) printf '#008000' ;;
        3) printf '#808000' ;;  4) printf '#000080' ;;  5) printf '#800080' ;;
        6) printf '#008080' ;;  7) printf '#c0c0c0' ;;  8) printf '#808080' ;;
        9) printf '#ff0000' ;; 10) printf '#00ff00' ;; 11) printf '#ffff00' ;;
       12) printf '#0000ff' ;; 13) printf '#ff00ff' ;; 14) printf '#00ffff' ;;
       15) printf '#ffffff' ;;
        *) return 0 ;;
    esac
}

# --- graphics protocol ------------------------------------------------------
# Two render paths exist. The sixel one draws through tmux, which parses the
# image and re-emits it, and is opaque because Konsole ignores sixel's
# transparency flag (P2=1): Vt102Emulation::hook() enters sixel mode on a bare
# 'q' and the canvas is an indexed image filled with register 0. The Kitty one
# goes straight to the terminal through tmux's DCS passthrough and has a real
# alpha channel, because Konsole keeps the frame as a QPixmap and blends it.

# catgraphics - which protocol to draw with: auto (default), sixel or kitty.
catgraphics() {
    local v
    v="$(catcfg CATWALK_GRAPHICS catwalk-graphics auto)"
    case "$v" in
        sixel | kitty | auto) printf '%s' "$v" ;;
        *) printf 'auto' ;;
    esac
}

# catkitty_ok - can we expect Kitty graphics to be understood? There is no way
# to ask: a query response comes back to tmux, which reads terminal replies
# itself rather than forwarding them to the pane, so probing would hang or
# leak the answer into somebody's shell as keystrokes. Recognise the terminals
# known to implement it instead, and let @catwalk-graphics kitty force it.
catkitty_ok() {
    # Konsole exports this into every pane, so it survives into tmux where
    # $TERM has become tmux-256color and tells us nothing.
    [[ -n "${KONSOLE_VERSION:-}" ]] && return 0
    case "${TERM_PROGRAM:-}" in
        WezTerm | ghostty | kitty) return 0 ;;
    esac
    case "${TERM:-}" in
        xterm-kitty | xterm-ghostty) return 0 ;;
    esac
    return 1
}

# catmode - the resolved render mode: "kitty" or "sixel".
#
# Transparency is opt-in and falls back rather than failing: it needs both
# @catwalk-bg transparent and a terminal that can do it, and if either is
# missing the opaque sixel path is used exactly as before. Emitting Kitty
# escapes at a terminal that does not understand them would print the base64
# payload as garbage, which is much worse than an opaque cat.
catmode() {
    local g
    g="$(catgraphics)"
    [[ "$g" == "sixel" ]] && { printf 'sixel'; return; }
    if [[ "$(catbg)" == "transparent" ]]; then
        if [[ "$g" == "kitty" ]] || catkitty_ok; then
            printf 'kitty'
            return
        fi
    fi
    printf 'sixel'
}

# --- absolute terminal coordinates ------------------------------------------
# A Kitty placement lands at the cursor (Screen::addPlacement takes _cuY/_cuX
# when row/col are -1), and tmux does not position a passthrough for us:
# tty_cmd_rawstring is tty_add() plus tty_invalidate() and nothing else. So the
# placement has to be preceded by an absolute CSI H, which means converting the
# pane's own coordinates into the terminal's.
#
# tmux's pane_top/pane_left are window-relative and 0-indexed; CSI H is
# terminal-absolute and 1-indexed. A status line at the top pushes the window
# down by however many rows it occupies, which is the client's height less the
# window's.

# catabsorigin <target> - print "ROW COL": the terminal-absolute, 1-indexed
# position of the pane's top-left cell. Empty when tmux cannot say.
catabsorigin() {
    local top left ch wh pos offset
    read -r top left ch wh < <(tmux display -p -t "$1" \
        '#{pane_top} #{pane_left} #{client_height} #{window_height}' 2>/dev/null)
    [[ "$top" =~ ^[0-9]+$ && "$left" =~ ^[0-9]+$ ]] || return 0
    offset=0
    if [[ "$ch" =~ ^[0-9]+$ && "$wh" =~ ^[0-9]+$ ]]; then
        pos="$(tmux show-options -gv status-position 2>/dev/null)"
        if [[ "$pos" == "top" ]]; then
            offset=$((ch - wh))
            ((offset < 0)) && offset=0
        fi
    fi
    printf '%d %d' "$((offset + top + 1))" "$((left + 1))"
}

# catresurrect_dir - where tmux-resurrect keeps its state, resolved the same way
# resurrect resolves it (@resurrect-dir, else the legacy ~/.tmux path if it
# exists, else XDG).
catresurrect_dir() {
    local d
    d="$(tmux show-options -gv @resurrect-dir 2>/dev/null)"
    if [[ -z "$d" ]]; then
        if [[ -d "$HOME/.tmux/resurrect" ]]; then
            d="$HOME/.tmux/resurrect"
        else
            d="${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect"
        fi
    fi
    d="${d//\$HOME/$HOME}"
    printf '%s' "${d/#\~/$HOME}"
}
