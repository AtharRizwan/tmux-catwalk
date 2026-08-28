# tmux-catwalk

A cat that walks across the top of every tmux window, rendered as a real
animated image - by default with the [Sixel](https://en.wikipedia.org/wiki/Sixel)
graphics protocol (needs a sixel-capable terminal such as Konsole, xterm, foot
or WezTerm, plus tmux >= 3.2).

Point `@catwalk-gif` at a *directory* instead of a single file and you get a
whole menagerie: critters wander in at random, one at a time or three at once,
each with its own GIF, its own speed and its own direction, with quiet gaps in
between. See [A directory of critters](#a-directory-of-critters).

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

Or point it at a directory of GIFs and let the spawner loose:

```tmux
set -g @catwalk-gif "$HOME/Pictures/catwalk"   # a directory, not a file
set -g @catwalk-direction random
set -g @catwalk-step "0.5-1"                   # a range, so they amble at different speeds
```

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
| `@catwalk-step`        | `1`                                        | cells advanced per tick, decimals allowed (`0.5`); `MIN-MAX` (e.g. `0.5-1`) gives the spawner a range to draw each critter's speed from |
| `@catwalk-direction`   | `rtl`                                      | `rtl` (right to left), `ltr`, or `random` for a direction per critter               |
| `@catwalk-gif`         | **(required)**                             | a walking-cat GIF, or a directory of them (see [A directory of critters](#a-directory-of-critters)) |
| `@catwalk-facing`      | `rtl`                                      | which way the artwork itself walks, so the spawner knows who to mirror; a file named `fox.ltr.gif` overrides it |
| `@catwalk-mirror`      | `1`                                        | flip the frames of a critter walking against its artwork; `0` to never mirror       |
| `@catwalk-max-cats`    | `3`                                        | roughly the busiest the strip gets; sets how often critters are born (directory mode) |
| `@catwalk-spawn`       | _(auto)_                                   | seconds between spawn chances; unset lets `@catwalk-max-cats` decide, a number pins it and overrides |
| `@catwalk-density`     | `70`                                       | percentage of spawn chances that actually produce a critter - how bunched up the arrivals are, not how many |
| `@catwalk-max-gifs`    | `0`                                        | cap on how many GIFs to take from a large directory (`0` = all)                     |
| `@catwalk-bind`        | `C`                                        | prefix key to toggle cats                                                           |
| `@catwalk-bg`          | _(auto)_                                   | background for the GIF's transparent pixels; empty = detect terminal bg, hex overrides, `transparent` = real alpha |
| `@catwalk-graphics`    | `auto`                                     | `auto`, `sixel` or `kitty` - which graphics protocol to draw with                   |
| `@catwalk-cache-dir`   | `${XDG_CACHE_HOME:-~/.cache}/tmux-catwalk` | render cache                                                                        |
| `@catwalk-sixel-check` | `1`                                        | refuse to spawn unless the attached client reports the `sixel` terminal feature (sixel path only) |

Every option also has a `CATWALK_*` environment override (`CATWALK_HEIGHT`,
`CATWALK_FPS`, ...) which takes precedence over the tmux option.

## A directory of critters

`@catwalk-gif` may name a single GIF or a directory. The two behave differently
on purpose:

- **A single GIF** walks end to end, continuously, wrapping at the edge. This is
  the original behaviour and nothing about it has changed.
- **A directory** turns on the spawner. Every `.gif` directly inside it joins the
  pool (subdirectories are ignored, symlinks are followed). A critter is born
  every few seconds - a random one from the pool, at a random speed within
  `@catwalk-step`, in a random direction if `@catwalk-direction` is `random` -
  walks one crossing, and is gone. `@catwalk-density` decides how many of those
  chances come to nothing, which is what puts the quiet gaps in.

### How busy the strip gets

`@catwalk-max-cats` is the one knob for this. It is a soft maximum rather than a
hard cap: the plugin works out how long a crossing takes on your pane at your
speeds, and spawns often enough to keep about two thirds of that many walking, so
the number you set reads as the busiest it usually gets. At the default of `3` on
a wide pane the strip is empty about 6% of the time, holds one 25%, two 37%,
three 24%, and occasionally four.

It cannot be a hard cap. Enforcing one means turning critters away, and a critter
turned away has to stay away for its whole crossing - re-decide it each tick and
it pops into existence halfway across the strip the moment room appears. The
rules that decide it once, at birth, are either far too pessimistic (size every
lane for the slowest crossing possible, which with a range like `1-3` leaves one
animal on screen nearly all the time) or unstable (ask whether the last critter
in that lane has left, and the answer depends on a chain of earlier such answers
that never settles). Letting the count vary around a target is the honest option,
and it is also what looks most like wildlife.

Turn `@catwalk-max-cats` down for a quieter strip and up for a busier one; it
scales about linearly. `@catwalk-density` does *not* change how many there are -
it cancels out - it changes how bunched up the arrivals are: low values mean
fewer, more clustered spawn chances and longer quiet stretches. Set
`@catwalk-spawn` to a number only if you want to pin the interval yourself, in
which case `@catwalk-max-cats` stops deciding anything.

None of that randomness is actually rolled. Every property of a critter is a
bit-field of a hash of the *spawn slot number*, so the whole menagerie stays a
pure function of the wall clock, exactly as a single cat's position always was.
That is what lets every window of a session show the same animals in the same
places, and a window opened mid-walk join what is already happening instead of
starting over.

### How fast they walk

`@catwalk-step` is cells per tick, and `@catwalk-fps` is ticks per second, so the
default `1` at `10` fps is ten columns a second - brisk. Decimals are allowed, and
a `MIN-MAX` range is what gives a pool its variety of gaits. What matters is how
long a crossing takes, which depends on how wide your pane is; on a 170-column
one:

| `@catwalk-step` | time to cross |
| --------------- | ------------- |
| `2`             | 8s            |
| `1`             | 16s           |
| `0.5-1`         | 16-33s        |
| `0.3-0.8`       | 20-54s        |
| `0.2-0.5`       | 33-82s        |

Speed does not change how many critters there are: the spawn interval is worked
out from how long a crossing takes, so slower critters simply arrive less often.
Set the pace with `@catwalk-step` and the crowd with `@catwalk-max-cats`; they do
not interfere.

Lowering `@catwalk-fps` also slows the walk, but it slows the *animation* with it
and the legs start to stutter. Use `@catwalk-step` for pace and leave the frame
rate alone.

### Mirroring

A critter walking against the way its artwork was drawn would moonwalk, so its
frames are mirrored (one `hflip` at extraction time, cached separately).
`@catwalk-facing` says which way the artwork walks; a directory holding critters
drawn both ways can say so per file, with a `.ltr.` or `.rtl.` before the
extension:

```
catwalk/
  maneki.gif        <- uses @catwalk-facing
  firefox.ltr.gif   <- drawn walking left to right
  stripes.rtl.gif   <- drawn walking right to left
```

### What it costs

The first launch renders every GIF in the pool - twice over when directions are
random, once per mirroring - which on the sixel path is a couple of seconds per
GIF while the pane sits empty. It is all cached on disk and shared between
windows, so every launch after that is instant. Frames are only read into a
cat's memory, and only handed to the terminal, the first time that critter
actually appears.

Drawing three critters costs three times what drawing one did. That matters on
the sixel path, where every frame is a whole image pushed through tmux; turn
`@catwalk-max-cats` down if it shows. On the transparent path a tick is still
just a handful of short escape sequences however many critters are walking.

### Limits

- Critters appear and disappear at the pane edges rather than sliding on and
  off: neither graphics protocol can clip an image mid-cell.
- Every GIF is scaled to `@catwalk-height`, so a pool of very different aspect
  ratios gives very different widths.
- `@catwalk-max-cats` is a target, not a ceiling - see
  [How busy the strip gets](#how-busy-the-strip-gets). Setting it very high runs
  into an internal limit of 16 simultaneous critters.
- A narrow pane makes for short crossings and therefore frequent spawns; a very
  wide one with a slow `@catwalk-step` makes for long ones and rarer arrivals.
  The plugin adjusts the interval for you either way, and re-adjusts on resize.

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
  chafa (cached, keyed by GIF + size + background + padding + protocol +
  mirroring), post-processes them with `sixelfill.py` to paint an opaque
  background under the sprite, and then walks the sprites across the pane.
- Frames are held in memory and each sprite's position is erased with a
  background-colored "cover" strip rather than a screen clear, so the animation
  costs a `sleep` and a `printf` per frame. Every cover for the tick is emitted
  before any sprite is: a later sixel placement draws over an earlier one, so
  erasing everybody first is what stops two overlapping critters from rubbing
  each other out.
- In directory mode each critter walks in a *lane*, and a lane is pure
  arithmetic: the critter born in spawn slot `k` uses lane `k % LANES`. There are
  as many lanes as the slowest possible crossing needs, so a lane is always clear
  before it comes round again - which is deliberately independent of
  `@catwalk-max-cats`, and means nothing ever has to be turned away for want of
  one. `@catwalk-max-cats` sets the spawn *rate* instead.
- On the transparent path the frames are not rendered to sixel at all.
  `catkitty.py` turns the extracted PNGs into one chunked Kitty
  `a=t` (transmit) blob per GIF, printed the first time that critter appears;
  each tick then only prints an
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

- **No cat appears**: ensure `@catwalk-gif` points to a valid GIF file, or to a
  directory containing at least one `.gif` (a bad path, or an empty directory,
  is reported in the status line) and that your terminal supports sixel -
  `tmux list-clients -F '#{client_termfeatures}'` must include `sixel`. That
  check is a sixel-path one; on the transparent path it is skipped, since tmux
  has no feature flag for Kitty graphics.
- **They walk too fast or too slowly**: `@catwalk-step`, which takes decimals -
  `0.5-1` is a comfortable amble on a wide pane, `0.2-0.5` a crawl. See
  [How fast they walk](#how-fast-they-walk). Do not reach for `@catwalk-fps`:
  it stutters the animation as well as slowing the walk.
- **Critters are too sparse, or too crowded**: `@catwalk-max-cats` is the knob -
  it scales about linearly, and the strip averages roughly two thirds of it.
  `@catwalk-density` will not help: it changes how clustered the arrivals are,
  not how many there are.
- **The first launch sits there empty**: every GIF in the directory is being
  rendered. It is cached; only the first run pays for it.
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
