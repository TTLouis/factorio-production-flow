"""Generate the 64x64 toolbar icon (graphics/icon.png). Run from anywhere."""
import os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
N, SS = 64, 4


def smooth(x):
    u = np.linspace(0, 1, 2049)
    return np.interp(x, 1.5 * u * (1 - u) + u ** 3, 3 * u ** 2 - 2 * u ** 3)


def main():
    n = N * SS
    img = np.zeros((n, n, 4), dtype=np.float64)
    xs = (np.arange(n) + 0.5) / n
    ys = (np.arange(n) + 0.5) / n
    x0, x1 = 0.16, 0.84
    t = np.clip((xs - x0) / (x1 - x0), 0, 1)
    # (y_left, y_right, thickness, rgb)
    ribbons = [
        (0.14, 0.50, 0.20, (0x4E, 0x9B, 0xE8)),
        (0.40, 0.14, 0.16, (0xE8, 0x86, 0x4E)),
        (0.62, 0.72, 0.22, (0x5C, 0xC2, 0x7A)),
    ]
    for yl, yr, th, rgb in ribbons:
        top = yl + (yr - yl) * smooth(t)
        m = (ys[:, None] >= top[None, :]) & (ys[:, None] <= top[None, :] + th)
        m &= ((xs >= x0) & (xs <= x1))[None, :]
        a = m.astype(float) * 0.9
        for c in range(3):
            img[..., c] = img[..., c] * (1 - a) + rgb[c] / 255 * a
        img[..., 3] = img[..., 3] * (1 - a) + a
    # node bars
    for bx in ((0.08, 0.16), (0.84, 0.92)):
        m = ((xs >= bx[0]) & (xs < bx[1]))[None, :] & ((ys >= 0.1) & (ys <= 0.9))[:, None]
        img[m] = (0.92, 0.92, 0.92, 1.0)
    out = img.reshape(N, SS, N, SS, 4).mean(axis=(1, 3))
    rgba = np.zeros((N, N, 4), dtype=np.uint8)
    a = out[..., 3:4]
    rgba[..., :3] = np.where(a > 0, out[..., :3] / np.maximum(a, 1e-6), 0).clip(0, 1) * 255
    rgba[..., 3] = (out[..., 3] * 255).round()
    Image.fromarray(rgba, "RGBA").save(os.path.join(ROOT, "graphics", "icon.png"))


if __name__ == "__main__":
    main()
