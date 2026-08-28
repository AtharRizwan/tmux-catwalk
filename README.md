# tmux-catwalk

A cat that walks across the top of every tmux window, rendered as a real
animated image - by default with the [Sixel](https://en.wikipedia.org/wiki/Sixel)
graphics protocol (needs a sixel-capable terminal such as Konsole, xterm, foot
or WezTerm, plus tmux >= 3.2).

Set `@catwalk-bg transparent` and the cat is drawn with the
[Kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/)
instead, which has a real alpha channel - so the GIF's transparent pixels are
genuinely transparent rather than filled with a background colour. See
[Transparency](#transparency).

## Requirements

- tmux >= 3.2
- `ffmpeg` and `ffprobe` (GIF frame extraction and aspect detection)
- `python3` (frame post-processing)
- a sixel-capable terminal, **or** one that speaks the Kitty graphics protocol
  (Konsole, kitty, Ghostty, WezTerm) if you want `@catwalk-bg transparent`
- `chafa` - sixel path only; the transparent path transmits the frames as PNG
  and never invokes it

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
| `@catwalk-height`      | `3`                                        | rows the cat occupies (the pane is one row taller on the sixel path)                |
| `@catwalk-width`       | _(auto)_                                   | exact columns the cat occupies; leave unset to auto-derive from height + GIF aspect |
| `@catwalk-cell-ratio`  | _(auto)_                                   | override the cell height/width used when deriving width (8x16 fonts `2.0`)          |
| `@catwalk-cell-px`     | _(auto)_                                   | override the cell size in pixels (`WxH`) the frames are rendered to                 |
| `@catwalk-top-pad`     | `1`                                        | 6px bands of headroom above the cat's head (shifts the cat down); `0` disables      |
| `@catwalk-fps`         | `10`                                       | animation frames per second                                                         |
| `@catwalk-step`        | `1`                                        | cells the cat advances per tick                                                     |
| `@catwalk-direction`   | `rtl`                                      | `rtl` (right to left) or `ltr`                                                      |
| `@catwalk-gif`         | **(required)**                             | path to a walking-cat GIF                                                           |
| `@catwalk-bind`        | `C`                                        | prefix key to toggle cats                                                           |
| `@catwalk-bg`          | _(auto)_                                   | background for the GIF's transparent pixels; empty = detect terminal bg, hex overrides, `transparent` = real alpha |
| `@catwalk-graphics`    | `auto`                                     | `auto`, `sixel` or `kitty` - which graphics protocol to draw with                   |
| `@catwalk-cache-dir`   | `${XDG_CACHE_HOME:-~/.cache}/tmux-catwalk` | render cache                                                                        |
| `@catwalk-sixel-check` | `1`                                        | refuse to spawn unless the attached client reports the `sixel` terminal feature (sixel path only) |

Every option also has a `CATWALK_*` environment override (`CATWALK_HEIGHT`,
`CATWALK_FPS`, ...) which takes precedence over the tmux option.

## Usage

- Cats appear automatically in every window (including the first one of a
  fresh session) while `@cats-on` is `1`.
- `prefix + C` toggles all cats off/on.
- Kill a cat pane any way you like (kill-pane, kill-window, kill-session,
  toggle) - the cat's graphics are discarded for you, so no ghost pixels are
  left behind (Konsole KDE bug 456354 workaround).
- **Every cat is in step.** Position and animation frame come from the wall
  clock rather than a per-cat counter, so all windows show the cat at the same
  spot on the same frame, and a window opened mid-walk joins in mid-stride
  instead of starting again from the edge.
- **Zoom hides the cat cleanly.** A zoomed pane is the only pane tmux draws
  (`prefix + z`, and `prefix + s`, which is `choose-tree -Zs`), so the cat's
  pane stops being rendered. It notices at once and drops its graphics, so
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

## Transparency

By default the cat sits on an opaque rectangle in your terminal's background
colour. That is a **Konsole** limitation rather than a sixel one, which is worth
being precise about because the two are easy to confuse:

- Sixel *can* signal transparency. `chafa` already emits it - `ESC P 0;1;0 q`,
  where the `1` is the "leave unpainted pixels alone" flag - and leaves the
  GIF's transparent pixels unpainted.
- tmux carries it faithfully. It parses that flag (`sixel_parse`) and re-emits
  it (`"\033P9;%uq"`).
- Konsole discards it. `Vt102Emulation::hook()` enters sixel mode on a bare `q`
  and never looks at the flag, and the canvas is an indexed image filled with
  colour register 0 - opaque. So unpainted pixels come out as *some* colour
  whatever we do.

Hence the default: paint the transparent area in the terminal's own background
colour so the rectangle blends in instead of reading as a black slab. The colour
is auto-detected from your active Konsole colour scheme (`[Background]`), or
failing that from `$COLORFGBG`. Set `@catwalk-bg` to a hex colour (e.g.
`#1e1e2e`) to force one.

On a semi-transparent or blurred terminal that still looks wrong, because a
solid rectangle cannot follow the blur. For that, ask for real transparency:

```tmux
set -g @catwalk-bg transparent
```

That switches the cat to the **Kitty graphics protocol**, which has an actual
alpha channel. Konsole keeps each frame as a pixmap and alpha-blends it over
whatever is behind, so the GIF's transparent pixels show your terminal
background - blur, translucency and all - and its anti-aliased edges blend
properly instead of being forced to one colour or none.

It is opt-in and falls back rather than failing: if the terminal is not one
known to support Kitty graphics, the opaque sixel path is used exactly as
before. `@catwalk-graphics` forces the choice either way (`kitty` to use it on a
terminal not on the list, `sixel` to keep the old path regardless).

Three things get better on the transparent path, all for the same reason - a
placement can be *deleted*, where a sixel can only be painted over:

- **No blink.** Toggling cats off or zooming a pane no longer cycles the
  alternate screen, so the screen does not flash.
- **Much less output.** A sixel tick writes the whole frame plus a cover strip,
  about 13 KB; a Kitty tick writes a place and a delete, about 90 bytes. Frames
  are transmitted once at startup and then only referenced.
- **Correct size everywhere.** Sixels are measured by tmux using the *window's*
  cell size, which can be stale (see the troubleshooting note below). Kitty
  frames never pass through tmux, so that failure mode does not exist.

The cat's strip is also a row shorter. A sixel pane needs one row of clearance
below the image, because tmux scrolls any sixel that reaches the last row;
nothing here passes through tmux, so the strip is exactly `@catwalk-height`
rows and `@catwalk-top-pad` is taken out of the image instead of out of the row
below it.

## How it works

- `session-created` / `after-new-window` hooks call `catensure`, which spawns
  one `catwalk` pane per window. Each cat stamps its pane with the `@catwalk`
  pane option; that option, not a pattern match on the pane's command, is how
  every other script recognises a cat.
- `catwalk` extracts the GIF frames with ffmpeg, renders them to sixel with
  chafa (cached, keyed by GIF + size + background + padding + protocol),
  post-processes them with `sixelfill.py` to paint an opaque background under
  the sprite, and then walks the sprite across the pane.
- Frames are held in memory and the cat's position is erased with a
  background-colored "cover" strip rather than a screen clear, so the animation
  costs a `sleep` and a `printf` per frame.
- On the transparent path the frames are not rendered to sixel at all.
  `catkitty.py` turns the extracted PNGs into one chunked Kitty
  `a=t` (transmit) blob, printed once at startup; each tick then only prints an
  absolute `CSI H`, an `a=p` (place) for the new frame and an `a=d,d=i` (delete)
  for the previous one, in a single passthrough payload. Because tmux never
  moves the cursor for passthrough output, the cat computes its own
  terminal-absolute origin from `pane_top`/`pane_left` and the status-bar
  position, and recomputes it whenever the layout changes.
- Position and frame index are computed from `$EPOCHREALTIME` divided by the
  frame period, and each frame sleeps to the *next* frame boundary rather than
  for a fixed delay. That is what keeps separate cats identical, and it is
  self-correcting: a slow frame is caught up instead of accumulating drift.
- `catpoke` runs on the `window-layout-changed` and `session-window-changed`
  hooks and sends each cat a `SIGUSR1`. Zoom hides the other panes without
  resizing them, so no `SIGWINCH` arrives, and a window switch changes no
  geometry at all; the signal is what lets a cat react to being hidden
  immediately rather than on its next periodic check.
- Only the cat in the window you are looking at draws, and on the transparent
  path that is the cat's own job rather than tmux's. Passthrough at the `all`
  level is forwarded from every window of the session - tmux checks only that
  the client's session holds the pane's window, not that the window is current
  - so each cat tracks whether its window is on screen and takes its placements
  down when it is not. Otherwise every window's cat would draw over the one
  window actually being displayed.
- `catsave` runs on resurrect's `post-save-layout` hook and records each cat's
  `session:window.pane` beside the state file; `catensure-all --restored` uses
  that record to `respawn-pane` those exact panes back into cats, re-checking
  each one's geometry first so it can never respawn over somebody's real pane.
- When a cat exits, or finds itself zoomed away, it discards its graphics. On
  the transparent path that is a plain delete of its own image ids, which is
  why the blink noted in troubleshooting does not happen there. On the sixel
  path it has to discard the terminal's whole sixel graphics layer: text and
  erase-display do not remove sixels on Konsole, but cycling the alternate
  screen buffer does. tmux is already *in* the alternate screen, so the
  sequence leaves it and comes back (`?1049l` then `?1049h`) - the other order
  clears just as well but strands the terminal in the primary buffer, losing
  pre-tmux scrollback and the screen restore on detach. `refresh-client` then
  repaints tmux's own content.

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
  `tmux list-clients -F '#{client_termfeatures}'` must include `sixel`. That
  check is a sixel-path one; on the transparent path it is skipped, since tmux
  has no feature flag for Kitty graphics.
- **Ghost pixels after toggle**: this is Konsole bug 456354, and it is
  specific to the sixel path. The exit trap clears the sixel layer
  automatically; if it persists, try `prefix + C` twice. On the transparent
  path the cat deletes its own placements by id, so there is nothing to leave
  behind.
- **The screen blinks when cats disappear**: expected on the sixel path.
  Discarding the sixel layer means cycling the alternate screen, and tmux
  repaints afterwards. It happens when cats are toggled off and when one is
  zoomed away - not on ordinary window switches, where the next window's cat
  simply paints over the last one. **This does not apply in transparent mode**:
  a Kitty placement can be deleted outright, so no alternate-screen cycle is
  needed and the screen never flashes.
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

  **This does not apply in transparent mode**: Kitty frames go straight to the
  terminal without tmux measuring them, so the stale value cannot affect their
  size at all. On the sixel path, catwalk bakes each cat to whatever its own
  window reports, so the cat comes out the right size either way. Fixing the stale value at the source is harder
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
