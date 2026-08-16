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
# The canvas can also be normalized to an explicit pixel size (--target WxH),
# so the image always occupies the same number of terminal cells no matter how
# chafa sizes its own canvas. Extra rows/columns are painted with the
# background color; --top-pad shifts the image down by 6-pixel bands, giving
# headroom above the cat's head (the same number of content bands are trimmed
# from the bottom only if the content would otherwise overflow the canvas).
#
# Usage:
#   sixelfill.py [fill] IN OUT R G B [--top-pad N] [--target WxH]
#     R G B   background color as 0-100 sixel channel values
#   sixelfill.py cover IN OUT R G B [--target WxH]
#     Emit a fill-only stream the same size as IN: an opaque rectangle in the
#     background color. The catwalk draws one of these over the previous frame
#     so only the newest cat stays visible.
#   sixelfill.py norm IN OUT
#     Rewrite IN with a bare-q DCS header and a guaranteed ST terminator, so
#     the stream survives tmux 3.7b's sixel detection (it only accepts DCS that
#     start with 'q' and end with ESC \ ).

import re
import sys


def read_stream(path):
    """Return (pre, payload, post) of the DCS payload in a .six file."""
    data = open(path, 'rb').read()
    m = re.search(rb'\x1bP[^q]*q(.*?)\x1b\\', data, re.S)
    if not m:
        m = re.search(rb'\x1bP[^q]*q(.*)', data, re.S)
    if not m:
        return None
    payload = m.group(1).decode('latin1')
    pre = data[:m.start(1)]
    mh = re.search(rb'\x1bP[^q]*q$', pre)
    if mh:
        pre = pre[:mh.start()] + b'\x1bPq'
    post = data[m.end(1):]
    if not post:
        post = b'\x1b\\\x1b[?25h'
    return pre, payload, post


def canvas_size(payload):
    cs = re.search(r'"1;1;(\d+);(\d+)', payload)
    if not cs:
        return 0, 0
    return int(cs.group(1)), int(cs.group(2))


def canvas_rewrite(payload, width, height):
    return re.sub(r'"1;1;\d+;\d+', '"1;1;%d;%d' % (width, height), payload, count=1)


def fill(path_in, path_out, r, g, b, top_pad=0, tw=0, th=0):
    sp = read_stream(path_in)
    if not sp:
        return False
    pre, payload, post = sp
    width, height = canvas_size(payload)
    if width <= 0 or height <= 0:
        return False
    if tw > 0 and th > 0:
        width, height = tw, th
        payload = canvas_rewrite(payload, width, height)

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
    if top_pad + len(pieces) > nbands:
        pieces = pieces[:max(nbands - top_pad, 0)]
    fillband = '#%d!%d~$' % (pen, width)

    if top_pad > 0:
        out = fillband
        for _ in range(1, top_pad):
            out += '-' + fillband
        for piece in pieces:
            out += '-' + fillband + piece
        for _ in range(top_pad + len(pieces), nbands):
            out += '-' + fillband
    elif pieces:
        out = fillband + pieces[0]
        for piece in pieces[1:]:
            out += '-' + fillband + piece
        for _ in range(len(pieces), nbands):
            out += '-' + fillband
    else:
        out = fillband

    out = payload[:i] + palette + '#%d;2;%d;%d;%d' % (pen, r, g, b) + out

    open(path_out, 'wb').write(pre + out.encode('latin1') + post)
    return True


def cover(path_in, path_out, r, g, b, tw=0, th=0):
    sp = read_stream(path_in)
    if not sp:
        return False
    pre, payload, post = sp
    width, height = canvas_size(payload)
    if width <= 0 or height <= 0:
        return False
    if tw > 0 and th > 0:
        width, height = tw, th
        payload = canvas_rewrite(payload, width, height)
    i = payload.index('#')

    fillband = '#0!%d~$' % width
    out = '#0;2;%d;%d;%d' % (r, g, b) + fillband
    for _ in range((height + 5) // 6 - 1):
        out += '-' + fillband

    open(path_out, 'wb').write(pre + payload[:i].encode('latin1') + out.encode('latin1') + post)
    return True


def norm(path_in, path_out):
    sp = read_stream(path_in)
    if not sp:
        return False
    pre, payload, post = sp
    open(path_out, 'wb').write(pre + payload.encode('latin1') + post)
    return True


def _parse_target(arg):
    m = re.match(r'^(\d+)x(\d+)$', arg)
    if not m:
        return 0, 0
    return int(m.group(1)), int(m.group(2))


if __name__ == '__main__':
    args = sys.argv[1:]
    mode = 'fill'
    if args and args[0] in ('fill', 'cover', 'norm'):
        mode = args[0]
        args = args[1:]

    if mode == 'norm':
        if len(args) != 2:
            print('usage: sixelfill.py norm IN OUT', file=sys.stderr)
            sys.exit(1)
        sys.exit(0 if norm(args[0], args[1]) else 2)

    tw = th = 0
    if '--target' in args:
        k = args.index('--target')
        if k + 1 < len(args):
            tw, th = _parse_target(args[k + 1])
            args = args[:k] + args[k + 2:]
    top_pad = 0
    if '--top-pad' in args:
        k = args.index('--top-pad')
        if k + 1 < len(args):
            top_pad = max(int(args[k + 1]), 0)
            args = args[:k] + args[k + 2:]

    if len(args) != 5:
        print('usage: sixelfill.py [fill|cover] IN OUT R G B [--top-pad N] [--target WxH]',
              file=sys.stderr)
        sys.exit(1)
    path_in, path_out = args[0], args[1]
    r, g, b = int(args[2]), int(args[3]), int(args[4])
    if mode == 'cover':
        ok = cover(path_in, path_out, r, g, b, tw, th)
    else:
        ok = fill(path_in, path_out, r, g, b, top_pad, tw, th)
    sys.exit(0 if ok else 2)
