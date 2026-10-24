"""Render the Balance favourite toggle icons: a gold star (on) and a grey outline (off)."""
import math
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE, SS = 32, 8


def star(radius_out, radius_in, n):
    c = n / 2
    pts = []
    for i in range(10):
        r = radius_out if i % 2 == 0 else radius_in
        a = -math.pi / 2 + i * math.pi / 5
        pts.append((c + r * n * math.cos(a), c + 0.04 * n + r * n * math.sin(a)))
    return pts


def render(path, fill, outline, width):
    n = SIZE * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    pts = star(0.47, 0.20, n)
    draw.polygon(pts, fill=fill)
    if outline:
        draw.line(pts + [pts[0]], fill=outline, width=int(width * SS), joint="curve")
    img.resize((SIZE, SIZE), Image.LANCZOS).save(path)


if __name__ == "__main__":
    graphics = os.path.join(ROOT, "graphics")
    render(os.path.join(graphics, "star.png"), (255, 200, 60, 255), (150, 95, 10, 255), 1.6)
    render(os.path.join(graphics, "star-off.png"), (0, 0, 0, 0), (170, 170, 170, 255), 2.2)
