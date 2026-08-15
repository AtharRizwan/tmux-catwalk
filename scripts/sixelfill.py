#!/usr/bin/env python3
# sixelfill.py - paint an opaque background under a chafa sixel stream.
#
# Sixel has no alpha. When chafa renders a transparent GIF, the pixels that
# stay unpainted are left to the terminal, and Konsole fills them with its
# sixel canvas color #0 - usually the cat's dark outline - which shows up as a
# blue/colored slab around the image.
#
# This tool rewrites a chafa .six file so every row of the canvas is painted:
# each band gets a full-width fill of a freshly-registered color (the terminal
# background) emitted before the band's own pixels, so the cat draws on top of
# it and the slab disappears.
#
# Usage: sixelfill.py IN OUT R G B
#   R G B     background color as 0-100 sixel channel values
# The canvas size is read from the .six canvas spec, so it needs no arguments.

import re
import sys


def fill(path_in, path_out, r, g, b, width=0, height=0):
    data = open(path_in, 'rb').read()

    m = re.search(rb'\x1bP[^q]*q(.*?)\x1b\\\\', data, re.S)
    if not m:
        m = re.search(rb'\x1bP[^q]*q(.*)', data, re.S)
    if not m:
        return False

    payload = m.group(1).decode('latin1')
    pre = data[:m.start(1)]
    post = data[m.end(1):]

    cs = re.search(r'"1;1;(\d+);(\d+)', payload)
    if cs:
        width, height = int(cs.group(1)), int(cs.group(2))
    if width <= 0 or height <= 0:
        return False

    i = payload.index('#')
    pat = re.compile(r'#(\d+);2;(\d+);(\d+);(\d+)')
    j = i
    pen = 0  # number of registered colors; first free index
    while True:
        mm = pat.match(payload[j:])
        if not mm:
            break
        pen += 1
        j += len(mm.group(0))
    palette = payload[i:j]
    stream = payload[j:]

    nbands = (height + 5) // 6
    pieces = stream.split('-')
    fill = '#%d!%d~$' % (pen, width)
    out = fill + pieces[0]
    for piece in pieces[1:]:
        out += '-' + fill + piece
    for _ in range(len(pieces), nbands):
        out += '-' + fill

    out = payload[:i] + palette + '#%d;2;%d;%d;%d' % (pen, r, g, b) + out

    open(path_out, 'wb').write(pre + out.encode('latin1') + post)
    return True


if __name__ == '__main__':
    args = sys.argv[1:]
    if len(args) < 5:
        print('usage: sixelfill.py IN OUT R G B', file=sys.stderr)
        sys.exit(1)
    if not fill(args[0], args[1], int(args[2]), int(args[3]), int(args[4])):
        sys.exit(2)
