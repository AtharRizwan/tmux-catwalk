#!/usr/bin/env python3
# catkitty.py - build the Kitty graphics payloads for the transparent path.
#
# The sixel path hands tmux an image and lets tmux re-emit it; this one goes
# straight to the terminal through tmux's DCS passthrough, because tmux has no
# idea what an APC graphics command is. The win is alpha: Konsole keeps the
# frame as a QPixmap and blends it (TerminalPainter::drawImagesAboveText), so
# the GIF's transparent pixels really are transparent - including its
# anti-aliased edges, which sixel cannot represent at all.
#
# Every frame is transmitted once, by id, and then merely *placed* each tick.
# Konsole holds transmitted frames in _graphicsImages for the life of the
# terminal, so the per-tick cost is two short escape sequences rather than a
# whole image.
#
# Usage:
#   catkitty.py transmit OUT ID_BASE PNG [PNG...]
#     Write the passthrough-wrapped transmission for every PNG to OUT, giving
#     the Nth frame image id ID_BASE+N.
#   catkitty.py idbase KEY
#     Print a stable image id base derived from KEY, so that cats sharing a
#     render cache share the terminal's copy of the frames and two different
#     GIFs (or sizes) never land on each other's ids.

import base64
import hashlib
import sys

ESC = '\033'

# Konsole rejects a command whose key section exceeds 1024 characters and
# base64-decodes each chunk on its own, so chunks must divide by 4.
CHUNK = 4092

# Kitty image ids are 32-bit. Stay well clear of the low numbers an image
# viewer sharing the terminal is likely to have picked.
ID_MIN = 1 << 20
ID_SPAN = 1 << 23


def passthrough(payload):
    """Wrap a raw escape payload for tmux's DCS passthrough.

    Every ESC inside the payload has to be doubled or tmux eats the sequence at
    its own terminator instead of forwarding it.
    """
    return ESC + 'Ptmux;' + payload.replace(ESC, ESC + ESC) + ESC + '\\'


def transmit_one(path, image_id):
    """Chunked a=t transmission of one PNG, already wrapped for passthrough."""
    data = base64.b64encode(open(path, 'rb').read()).decode('ascii')
    out = []
    for off in range(0, len(data), CHUNK):
        part = data[off:off + CHUNK]
        more = 1 if off + CHUNK < len(data) else 0
        if off == 0:
            # f=100 is not a size Konsole special-cases, so it falls through to
            # QPixmap::loadFromData, which sniffs the PNG header. t=d is the
            # only transmission medium it accepts. q=2 suppresses the reply -
            # under tmux a reply would arrive as keystrokes in somebody's shell.
            keys = 'a=t,i=%d,f=100,t=d,q=2,m=%d' % (image_id, more)
        else:
            # Konsole remembers the first chunk's keys in savedKeys, so the
            # continuations need carry only the chunking state.
            keys = 'a=t,m=%d,q=2' % more
        out.append(passthrough('%s_G%s;%s%s\\' % (ESC, keys, part, ESC)))
    return ''.join(out)


def transmit(path_out, id_base, paths):
    out = []
    for n, path in enumerate(paths):
        out.append(transmit_one(path, id_base + n))
    open(path_out, 'w', encoding='latin1').write(''.join(out))
    return True


def idbase(key):
    h = hashlib.md5(key.encode('utf-8', 'replace')).hexdigest()
    return ID_MIN + int(h[:8], 16) % ID_SPAN


if __name__ == '__main__':
    args = sys.argv[1:]
    if len(args) >= 2 and args[0] == 'idbase':
        print(idbase(args[1]))
        sys.exit(0)
    if len(args) >= 4 and args[0] == 'transmit':
        try:
            base = int(args[2])
        except ValueError:
            print('catkitty.py: ID_BASE must be an integer', file=sys.stderr)
            sys.exit(1)
        sys.exit(0 if transmit(args[1], base, args[3:]) else 2)
    print('usage: catkitty.py transmit OUT ID_BASE PNG [PNG...]\n'
          '       catkitty.py idbase KEY', file=sys.stderr)
    sys.exit(1)
