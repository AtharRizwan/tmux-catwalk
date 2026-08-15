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

# cache dir shared by catwalk, catclear, catwatchdog
catcache() {
    catcfg CATWALK_CACHE catwalk-cache-dir "${XDG_CACHE_HOME:-$HOME/.cache}/tmux-catwalk"
}

# catbg - best-effort opaque background for transparent pixels. Sixel has no
# alpha channel, so chafa has to paint those pixels some color; matching the
# terminal's own background makes the box blend in instead of reading as a
# black (or blue) slab. Precedence: $CATWALK_BG / @catwalk-bg, else the active
# Konsole color scheme's [Background] Color, else empty (chafa assumes black).
catbg() {
    local v profile scheme file sec r g b
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
    [[ -n "$scheme" ]] || return 0

    file="$HOME/.local/share/konsole/$scheme.colorscheme"
    [[ -f "$file" ]] || file="/usr/share/konsole/ColorSchemes/$scheme.colorscheme"
    [[ -f "$file" ]] || return 0

    v="$(awk -F= '/^\[[^]]*\]/{sec=$0} sec=="[Background]" && $1=="Color"{print $2; exit}' "$file")"
    [[ -n "$v" ]] || return 0

    v="${v// /}"
    IFS=, read -r r g b <<< "$v"
    if [[ "$r" =~ ^[0-9]+$ && "$g" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ ]]; then
        printf '#%02x%02x%02x' "$((r<256 ? r : 255))" "$((g<256 ? g : 255))" "$((b<256 ? b : 255))"
    fi
}
