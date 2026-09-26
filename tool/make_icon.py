"""Draws the 1024px app icon (full-bleed honey wood with a 'W') and writes iOS + Android sizes. Needs Pillow."""
import json, math, os, random
from PIL import Image, ImageDraw, ImageFont

N = 1024
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def lerp(a, b, t): return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))

tile = (0xE3, 0xB0, 0x5C)  # honey oak

# full-bleed wood: iOS masks the corners itself, so no background or border
img = Image.new('RGB', (N, N))
d = ImageDraw.Draw(img)
light, dark = lerp(tile, (255, 255, 255), .18), lerp(tile, (0, 0, 0), .18)
for y in range(N):
    t = y / N
    d.line([(0, y), (N, y)], fill=lerp(light, tile, t * 2) if t < .5 else lerp(tile, dark, t * 2 - 1))
rng = random.Random(4)
grain = lerp(tile, (0x3E, 0x27, 0x23), .22)
for i in range(14):
    y0 = N * (i + rng.random()) / 14
    amp, freq, ph, w = 4 + rng.random() * 10, .5 + rng.random() * 1.2, rng.random() * 6.3, rng.choice([2, 3, 4])
    d.line([(x, y0 + amp * math.sin(ph + freq * 2 * math.pi * x / N)) for x in range(0, N + 8, 8)], fill=grain, width=w)
for k in range(3):
    rr = 16 + k * 18
    d.ellipse((230 - rr * 1.8, 850 - rr, 230 + rr * 1.8, 850 + rr), outline=grain, width=4)

# the W
font = ImageFont.truetype(os.path.join(root, 'assets/fonts/Fredoka.ttf'), 640)
font.set_variation_by_axes([700, 100])  # Fredoka axes: wght, wdth
cx, cy = N / 2, N / 2 - 10
d.text((cx + 8, cy + 18), 'W', font=font, anchor='mm', fill=lerp(tile, (0, 0, 0), .45))
d.text((cx, cy), 'W', font=font, anchor='mm', fill=(0x4A, 0x2F, 0x1B))

os.makedirs(os.path.join(root, 'assets'), exist_ok=True)
img.save(os.path.join(root, 'assets/icon.png'))

# iOS: fill every slot in the existing AppIcon set
ios = os.path.join(root, 'ios/Runner/Assets.xcassets/AppIcon.appiconset')
for e in json.load(open(os.path.join(ios, 'Contents.json')))['images']:
    px = round(float(e['size'].split('x')[0]) * int(e['scale'][0]))
    img.resize((px, px), Image.LANCZOS).save(os.path.join(ios, e['filename']))

# Android legacy launcher icons: Android doesn't mask these, so round the corners here
mask = Image.new('L', (N, N), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, N - 1, N - 1), 225, fill=255)
rounded = img.convert('RGBA')
rounded.putalpha(mask)
for folder, px in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
    rounded.resize((px, px), Image.LANCZOS).save(os.path.join(root, f'android/app/src/main/res/mipmap-{folder}/ic_launcher.png'))
print('icon written')
