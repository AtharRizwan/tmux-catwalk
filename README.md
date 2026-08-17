# tmux-catwalk

A cat that walks across the top of every tmux window, rendered as a real
animated image with the [Sixel](https://en.wikipedia.org/wiki/Sixel) graphics
protocol (needs a sixel-capable terminal such as Konsole, xterm, foot or
WezTerm, plus tmux >= 3.2).

## Requirements

- tmux >= 3.2
- a sixel-capable terminal
- `ffmpeg` (GIF frame extraction)
- `chafa` (sixel rendering)

## Install (tpm)

```tmux
set -g @plugin 'AtharRizwan/tmux-catwalk'
```

press `prefix + I`.

Then set your walking cat GIF (required):

```tmux
set -g @catwalk-gif '~/Pictures/walking-cat.gif'
```

## Options

| option                 | default                                    | description                                                                         |
| ---------------------- | ------------------------------------------ | ----------------------------------------------------------------------------------- |
| `@cats-on`             | `1`                                        | master switch (0/1)                                                                 |
| `@catwalk-height`      | `3`                                        | rows the cat occupies                                                               |
| `@catwalk-width`       | _(auto)_                                   | max columns the cat may occupy; leave unset to auto-derive from height + GIF aspect |
| `@catwalk-cell-ratio`  | `2.4`                                      | terminal cell height/width used when deriving width (8x16 fonts ~2.0)               |
| `@catwalk-fps`         | `10`                                       | animation frames per second                                                         |
| `@catwalk-step`        | `1`                                        | cells the cat advances per tick                                                     |
| `@catwalk-gif`         | **(required)**                             | path to a walking-cat GIF                                                           |
| `@catwalk-bind`        | `C`                                        | prefix key to toggle cats                                                           |
| `@catwalk-bg`          | _(auto)_                                   | background for the GIF's transparent pixels; empty = detect terminal bg, hex overrides |
| `@catwalk-cache-dir`   | `${XDG_CACHE_HOME:-~/.cache}/tmux-catwalk` | sixel render cache                                                                  |
| `@catwalk-sixel-check` | `1`                                        | refuse to spawn if `terminal-features` lacks `sixel`                                |

## Usage

- Cats appear automatically in every window (including the first one of a
  fresh session) while `@cats-on` is `1`.
- `prefix + C` toggles all cats off/on.
- Kill a cat pane any way you like (kill-pane, kill-window, kill-session,
  toggle) - the terminal's sixel graphics layer is discarded for you, so no
  ghost pixels are left behind (Konsole KDE bug 456354 workaround).
- Works with tmux-resurrect / tmux-continuum: cats come back after a restore
  and are never duplicated.

## Why is there a background behind the cat?

The GIF is transparent, but the **sixel protocol has no alpha channel**, so
every pixel must be an opaque color. `chafa` fills the transparent areas with
a background color instead of leaving them see-through. By default `@catwalk-bg`
is empty and the background is auto-detected from your active Konsole color
scheme (`[Background]` color), so the box blends into the terminal instead of
reading as a black slab. On a semi-transparent terminal you will still see a
solid rectangle - sixel simply cannot be translucent - but it will match the
terminal's own background. Set `@catwalk-bg` to a hex color (e.g.
`#1e1e2e`) to force a specific fill.

## How it works

- `session-created` / `after-new-window` hooks call `catensure`, which spawns
  one `catwalk` pane per window.
- `catwalk` extracts the GIF frames with ffmpeg, renders them to sixel with
  chafa (cached, keyed by GIF + size), and animates a full-width strip.
- Each `catwalk` spawns a detached `catwatchdog`; when the cat dies for any
  reason the watchdog toggles the alternate screen via a tiny popup, which
  makes the terminal discard the sixel graphics layer.

## Troubleshooting

- **No cat appears**: ensure `@catwalk-gif` points to a valid GIF file and
  your terminal supports sixel (`terminal-features` must include `sixel`).
- **Ghost pixels after toggle**: this is Konsole bug 456354. The watchdog
  clears the sixel layer automatically; if it persists, try `prefix + C`
  again or `tmux run-shell ~/.config/tmux/plugins/tmux-catwalk/scripts/catclear`.
- **Cat looks stretched/squished**: tune `@catwalk-cell-ratio` to match your
  font's cell dimensions (measure a character in pixels).
