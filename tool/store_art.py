"""Renders App Store header / search-results art at full resolution (python3 tool/store_art.py)."""
import math, random
from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT = 'assets/fonts/Fredoka.ttf'
TILES = [((160, 202, 169), (98, 132, 106)), ((237, 208, 127), (170, 145, 78)), ((214, 182, 135), (150, 123, 86))]
INK = (74, 46, 26)
BG_TOP, BG_BOT = (249, 240, 228), (221, 239, 230)


def font(px):
    f = ImageFont.truetype(FONT, px)
    try:
        f.set_variation_by_name('Bold')
    except Exception:
        pass
    return f


def background(w, h):
    bg = Image.new('RGB', (w, h))
    d = ImageDraw.Draw(bg)
    for y in range(h):
        t = y / (h - 1)
        d.line([(0, y), (w, y)], fill=tuple(round(a * (1 - t) + b * t) for a, b in zip(BG_TOP, BG_BOT)))
    return bg


def tile(letter, i, s):
    face, edge = TILES[i % 3]
    r, depth = s // 6, s // 14
    im = Image.new('RGBA', (s + s // 4, s + depth + s // 4), (0, 0, 0, 0))
    o = s // 8
    sh = Image.new('RGBA', im.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([o, o + depth * 1.6, o + s, o + s + depth * 1.6], r, fill=(60, 40, 20, 90))
    im = Image.alpha_composite(im, sh.filter(ImageFilter.GaussianBlur(s // 18)))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([o, o + depth, o + s, o + s + depth], r, fill=edge)
    d.rounded_rectangle([o, o, o + s, o + s], r, fill=face)
    rnd = random.Random(i * 7 + 3)  # wood grain
    grain = tuple(max(0, c - 22) for c in face) + (110,)
    g = Image.new('RGBA', im.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(g)
    for k in range(5):
        y0, amp, ph = o + s * (0.12 + 0.19 * k) + rnd.uniform(-6, 6), s * 0.025, rnd.uniform(0, 6)
        pts = [(o + x, y0 + amp * math.sin(ph + x / s * 6)) for x in range(0, s + 1, max(1, s // 40))]
        gd.line(pts, fill=grain, width=max(2, s // 90))
    mask = Image.new('L', im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([o, o, o + s, o + s], r, fill=255)
    im.paste(g, (0, 0), Image.composite(g, Image.new('RGBA', im.size), mask).getchannel('A'))
    d = ImageDraw.Draw(im)
    d.text((o + s / 2, o + s / 2 + s * 0.03), letter, font=font(int(s * 0.56)), fill=INK, anchor='mm')
    return im


def logo(word, s, gap):
    tiles = [tile(ch, i, s) for i, ch in enumerate(word)]
    tw, th = tiles[0].size
    step = s + gap
    im = Image.new('RGBA', (step * (len(word) - 1) + tw, th), (0, 0, 0, 0))
    for i, t in enumerate(tiles):
        im.alpha_composite(t, (i * step, 0))
    return im


def phone(path, height):
    shot = Image.open(path).convert('RGB')
    w = round(shot.width * height / shot.height)
    shot = shot.resize((w, height), Image.LANCZOS)
    bez, r = height // 40, height // 14
    im = Image.new('RGBA', (w + 2 * bez + height // 10, height + 2 * bez + height // 10), (0, 0, 0, 0))
    sh = Image.new('RGBA', im.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([height // 20, height // 14, height // 20 + w + 2 * bez, height // 14 + height + 2 * bez], r + bez, fill=(40, 30, 20, 80))
    im = Image.alpha_composite(im, sh.filter(ImageFilter.GaussianBlur(height // 50)))
    x0, y0 = height // 20, height // 20
    ImageDraw.Draw(im).rounded_rectangle([x0, y0, x0 + w + 2 * bez, y0 + height + 2 * bez], r + bez, fill=(40, 32, 26))
    m = Image.new('L', shot.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w, height], r, fill=255)
    im.paste(shot, (x0 + bez, y0 + bez), m)
    return im


def compose(w, h, phones, out):
    bg = background(w, h).convert('RGBA')
    ph = int(h * 0.86)
    x = w - int(w * 0.03)
    for p in reversed(phones):
        pi = phone(p, ph)
        x -= pi.width - int(ph * 0.04)
        bg.alpha_composite(pi, (x, (h - pi.height) // 2 + int(h * 0.02)))
    left = int(w * 0.05)
    room = x - left - int(w * 0.03)  # logo + text must fit left of the phones
    s = min(int(h * 0.13), int(room / (7 * 1.13 + 0.25)))
    lg = logo('WORDSIM', s, int(s * 0.13))
    top = (h - lg.height - int(s * 1.5)) // 2
    bg.alpha_composite(lg, (left, top))
    d = ImageDraw.Draw(bg)
    tx, y = left + s // 8, top + lg.height + int(s * 0.25)
    for text, size, col in [('crack the hidden word', 0.62, (140, 95, 60)), ('4 to 7 letters  ·  hints  ·  daily streaks', 0.36, (150, 120, 90))]:
        f = font(int(s * size))
        while d.textlength(text, font=f) > room - s // 8:
            f = font(f.size - 2)
        d.text((tx, y), text, font=f, fill=col)
        y += int(f.size * 1.35)
    bg.convert('RGB').save(out)


S = 'store/ios/iphone63_'
compose(3840, 1646, [S + '2.png', S + '3.png', S + '4.png'], 'store/ios/header_3840x1646.png')
compose(1920, 1280, [S + '4.png'], 'store/ios/search_1920x1280.png')
