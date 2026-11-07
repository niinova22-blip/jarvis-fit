"""NOVA Coach app icon (1024x1024, opaque RGB as App Store requires).

Deep-space background, violet nebula glow, a rotating-arc ring and a four-pointed "nova" star
in lime fading to white. Matches the in-app orb (JarvisFit/DesignSystem/Theme.swift).

    python tools/brand/make_icon.py [output.png]
"""
import math
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 1024
BG = (7, 6, 12)
LIME = (200, 255, 46)
VIOLET = (138, 107, 255)


def radial(size, center, radius, color, strength):
    """Soft radial glow as an RGB layer to be added onto the background."""
    layer = Image.new("RGB", (size, size), (0, 0, 0))
    px = layer.load()
    cx, cy = center
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - cx, y - cy) / radius
            if d < 1:
                k = (1 - d) ** 2.2 * strength
                px[x, y] = tuple(int(c * k) for c in color)
    return layer


def star(draw, center, r_outer, r_inner, fill):
    cx, cy = center
    pts = []
    for i in range(8):
        a = i * math.pi / 4 - math.pi / 2
        r = r_outer if i % 2 == 0 else r_inner
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    draw.polygon(pts, fill=fill)


def main(out):
    img = Image.new("RGB", (S, S), BG)
    img = ImageChops.add(img, radial(S, (S * 0.72, S * 0.22), S * 0.85, VIOLET, 0.55))
    img = ImageChops.add(img, radial(S, (S * 0.5, S * 0.5), S * 0.42, VIOLET, 0.45))
    img = ImageChops.add(img, radial(S, (S * 0.25, S * 0.9), S * 0.6, LIME, 0.10))

    c = (S / 2, S / 2)

    # Arc ring (gradient from transparent to lime), drawn at 2x then blurred slightly.
    ring = Image.new("RGB", (S, S), (0, 0, 0))
    rd = ImageDraw.Draw(ring)
    r = S * 0.36
    steps = 260
    for i in range(steps):
        t = i / steps
        a0 = -200 + t * 260
        k = t ** 1.6
        col = tuple(int(v * k) for v in LIME)
        rd.arc([c[0] - r, c[1] - r, c[0] + r, c[1] + r], a0, a0 + 1.6, fill=col, width=int(S * 0.034))
    img = ImageChops.add(img, ring.filter(ImageFilter.GaussianBlur(14)))
    img = ImageChops.add(img, ring)

    # Star glow.
    glow = Image.new("RGB", (S, S), (0, 0, 0))
    star(ImageDraw.Draw(glow), c, S * 0.27, S * 0.075, LIME)
    img = ImageChops.add(img, glow.filter(ImageFilter.GaussianBlur(40)))
    img = ImageChops.add(img, glow.filter(ImageFilter.GaussianBlur(12)))

    # Star body: lime with a white-hot core.
    body = Image.new("RGB", (S, S), (0, 0, 0))
    star(ImageDraw.Draw(body), c, S * 0.25, S * 0.07, LIME)
    mask = Image.new("L", (S, S), 0)
    star(ImageDraw.Draw(mask), c, S * 0.25, S * 0.07, 255)
    img.paste(body, (0, 0), mask)
    core = radial(S, c, S * 0.13, (255, 255, 255), 1.0)
    img = Image.composite(ImageChops.add(img, core), img, mask)

    img.save(out, "PNG")
    print("wrote", out)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "JarvisFit/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
