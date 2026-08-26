# tmux-catwalk

A cat that walks across the top of every tmux window, rendered as a real
animated image with the [Sixel](https://en.wikipedia.org/wiki/Sixel) graphics
protocol (needs a sixel-capable terminal such as Konsole, xterm, foot or
WezTerm, plus tmux >= 3.2).

## Requirements

- tmux >= 3.2
- a sixel-capable terminal
- `ffmpeg` and `ffprobe` (GIF frame extraction and aspect detection)
- `chafa` (sixel rendering)
- `python3` (sixel post-processing)

`flock` is used when present to serialise the first render across windows.
Nothing needs `allow-passthrough` set globally - each cat raises the level on
its own pane.

## Install (tpm)

```tmux
set -g @plugin 'AtharRizwan/tmux-catwalk'
```

press `prefix + I`.

Then set your walking cat GIF (required):

```tmux
set -g @catwalk-gif "$HOME/Pictures/walking-cat.gif"
```

Use double quotes with `$HOME` rather than single quotes with `~`: tmux does not
expand a tilde inside a single-quoted option value. (A leading `~` is expanded
as a courtesy, but `$HOME` is the form that always works.)

## Options

| option                 | default                                    | description                                                                         |
| ---------------------- | ------------------------------------------ | ----------------------------------------------------------------------------------- |
| `@cats-on`             | `1`                                        | master switch (0/1)                                                                 |
| `@catwalk-height`      | `3`                                        | rows the cat occupies                                                               |
| `@catwalk-width`       | _(auto)_                                   | exact columns the cat occupies; leave unset to auto-derive from height + GIF aspect |
| `@catwalk-cell-ratio`  | _(auto)_                                   | override the cell height/width used when deriving width (8x16 fonts `2.0`)          |
| `@catwalk-cell-px`     | _(auto)_                                   | override the cell size in pixels (`WxH`) the sixel canvas is normalised to          |
| `@catwalk-top-pad`     | `1`                                        | 6px bands of headroom above the cat's head (shifts the cat down); `0` disables      |
| `@catwalk-fps`         | `10`                                       | animation frames per second                                                         |
| `@catwalk-step`        | `1`                                        | cells the cat advances per tick                                                     |
| `@catwalk-direction`   | `rtl`                                      | `rtl` (right to left) or `ltr`                                                      |
| `@catwalk-gif`         | **(required)**                             | path to a walking-cat GIF                                                           |
| `@catwalk-bind`        | `C`                                        | prefix key to toggle cats                                                           |
| `@catwalk-bg`          | _(auto)_                                   | background for the GIF's transparent pixels; empty = detect terminal bg, hex overrides |
| `@catwalk-cache-dir`   | `${XDG_CACHE_HOME:-~/.cache}/tmux-catwalk` | sixel render cache                                                                  |
| `@catwalk-sixel-check` | `1`                                        | refuse to spawn unless the attached client reports the `sixel` terminal feature     |

Every option also has a `CATWALK_*` environment override (`CATWALK_HEIGHT`,
`CATWALK_FPS`, ...) which takes precedence over the tmux option.

## Usage

- Cats appear automatically in every window (including the first one of a
  fresh session) while `@cats-on` is `1`.
- `prefix + C` toggles all cats off/on.
- Kill a cat pane any way you like (kill-pane, kill-window, kill-session,
  toggle) - the terminal's sixel graphics layer is discarded for you, so no
  ghost pixels are left behind (Konsole KDE bug 456354 workaround).
- **Every cat is in step.** Position and animation frame come from the wall
  clock rather than a per-cat counter, so all windows show the cat at the same
  spot on the same frame, and a window opened mid-walk joins in mid-stride
  instead of starting again from the edge.
- **Zoom hides the cat cleanly.** A zoomed pane is the only pane tmux draws
  (`prefix + z`, and `prefix + s`, which is `choose-tree -Zs`), so the cat's
  pane stops being rendered. It notices at once and drops the sixel layer, so
  nothing of it is left over the chooser; it is back as soon as you unzoom.
- **Closing the last other pane closes the window.** The cat exits within a
  frame of being left alone rather than lingering, and it stays in its strip
  while it does, instead of following the pane's bottom edge down the screen.
- Works with tmux-resurrect / tmux-continuum: resurrect brings panes back as
  plain shells, so a saved cat would otherwise return as a dead strip with a
  fresh cat added beside it - one more strip per window per restore. Instead
  the save records where the cats were and the restore reclaims exactly those
  panes, so the restored layout matches the saved one and cats are never
  duplicated.

## Why is there a background behind the cat?

The GIF is transparent, but the **sixel protocol has no alpha channel**, so
every pixel must be an opaque color. `chafa` fills the transparent areas with
a background color instead of leaving them see-through. By default `@catwalk-bg`
is empty and the background is auto-detected - from your active Konsole color
scheme (`[Background]` color), or failing that from `$COLORFGBG` - so the box
blends into the terminal instead of reading as a black slab. On a
semi-transparent terminal you will still see a solid rectangle - sixel simply
cannot be translucent - but it will match the terminal's own background. Set
`@catwalk-bg` to a hex color (e.g. `#1e1e2e`) to force a specific fill.

## How it works

- `session-created` / `after-new-window` hooks call `catensure`, which spawns
  one `catwalk` pane per window. Each cat stamps its pane with the `@catwalk`
  pane option; that option, not a pattern match on the pane's command, is how
  every other script recognises a cat.
- `catwalk` extracts the GIF frames with ffmpeg, renders them to sixel with
  chafa (cached, keyed by GIF + size + background + padding), post-processes
  them with `sixelfill.py` to paint an opaque background under the sprite, and
  then walks the sprite across the pane.
- Frames are held in memory and the cat's position is erased with a
  background-colored "cover" strip rather than a screen clear, so the animation
  costs a `sleep` and a `printf` per frame.
- Position and frame index are computed from `$EPOCHREALTIME` divided by the
  frame period, and each frame sleeps to the *next* frame boundary rather than
  for a fixed delay. That is what keeps separate cats identical, and it is
  self-correcting: a slow frame is caught up instead of accumulating drift.
- `catpoke` runs on the `window-layout-changed` hook and sends each cat a
  `SIGUSR1`. Zoom hides the other panes without resizing them, so no `SIGWINCH`
  arrives; the signal is what lets a cat react to being hidden immediately
  rather than on its next periodic check.
- `catsave` runs on resurrect's `post-save-layout` hook and records each cat's
  `session:window.pane` beside the state file; `catensure-all --restored` uses
  that record to `respawn-pane` those exact panes back into cats, re-checking
  each one's geometry first so it can never respawn over somebody's real pane.
- When a cat exits, or finds itself zoomed away, it discards the terminal's
  sixel graphics layer: text and erase-display do not remove sixels on Konsole,
  but cycling the alternate screen buffer does. tmux is already *in* the
  alternate screen, so the sequence leaves it and comes back (`?1049l` then
  `?1049h`) - the other order clears just as well but strands the terminal in
  the primary buffer, losing pre-tmux scrollback and the screen restore on
  detach. `refresh-client` then repaints tmux's own content.

That escape reaches the terminal through tmux's DCS passthrough, which the cat
enables **on its own pane only**:

```tmux
set -p allow-passthrough all      # done for you, per cat pane
```

`allow-passthrough` is a pane option, so this needs no change to your global
setting and grants nothing to any other pane. The `all` level matters because
the plain `on` level only forwards passthrough from a *visible* pane - which is
exactly the case a zoomed-away cat needs to clear itself out of.

## Troubleshooting

- **No cat appears**: ensure `@catwalk-gif` points to a valid GIF file (a bad
  path is reported in the status line) and that your terminal supports sixel -
  `tmux list-clients -F '#{client_termfeatures}'` must include `sixel`.
- **Ghost pixels after toggle**: this is Konsole bug 456354. The exit trap
  clears the sixel layer automatically; if it persists, try `prefix + C` twice.
- **The screen blinks when cats disappear**: expected. Discarding the sixel
  layer means cycling the alternate screen, and tmux repaints afterwards. It
  happens when cats are toggled off and when one is zoomed away - not on
  ordinary window switches, where the next window's cat simply paints over the
  last one.
- **Cat looks stretched/squished**: both cell settings are detected from tmux
  at render time, so this should not happen. If it does, pin them: set
  `@catwalk-cell-ratio` to your font's cell height/width and `@catwalk-cell-px`
  to its exact pixel size.
- **Cat is smaller in some windows than others**: tmux measures a sixel in cells
  using the *window's* `#{window_cell_width}`/`#{window_cell_height}`, and
  `recalculate_size()` only refreshes those when a window's **character** size
  changes -- so a window restored at the client's exact size keeps tmux's 16x32
  default for good and reads every image at the wrong scale. Compare them:

  ```sh
  tmux list-windows -a -F '#{window_name} #{window_cell_width}x#{window_cell_height}'
  tmux display -p '#{client_cell_width}x#{client_cell_height}'
  ```

  Catwalk bakes each cat to whatever its own window reports, so the cat comes
  out the right size either way. Fixing the stale value at the source is harder
  than it looks: `default_window_size()` leaves the pixel fields at `0` for a
  manually sized window and `window_resize()` turns `0` into
  `DEFAULT_XPIXEL`/`DEFAULT_YPIXEL`, so `resize-window` and `window-size manual`
  *pin* a window to 16x32 rather than fixing it. Only a client-driven recalculate
  that actually changes the character size -- resizing the terminal, or
  detaching and reattaching at a different size -- writes the real value back.
- **Cat sits too low / its feet are clipped**: lower `@catwalk-top-pad`, or set
  it to `0`.

## License

MIT - see [LICENSE](LICENSE).
