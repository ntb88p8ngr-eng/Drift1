"""Generate seamless, tileable surface maps for the Tokyo Midnight Circuit project."""
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter

OUT = Path(__file__).resolve().parents[1] / "textures"
N = 512
Y, X = np.mgrid[0:N, 0:N]


def periodic_noise(seed, octaves=(2, 4, 8, 16, 32, 64)):
    rng = np.random.default_rng(seed)
    xx = X / N
    yy = Y / N
    result = np.zeros((N, N), dtype=np.float32)
    weights = [1 / (i + 1) ** 0.75 for i in range(len(octaves))]
    for freq, weight in zip(octaves, weights):
        phase = rng.uniform(0, 2 * np.pi)
        angle = rng.uniform(0, 2 * np.pi)
        kx = max(1, int(round(freq * np.cos(angle))))
        ky = max(1, int(round(freq * np.sin(angle))))
        result += weight * np.sin(2 * np.pi * (kx * xx + ky * yy) + phase)
        phase2 = rng.uniform(0, 2 * np.pi)
        result += weight * 0.45 * np.cos(2 * np.pi * (ky * xx - kx * yy) + phase2)
    result -= result.min()
    result /= max(result.max(), 1e-6)
    return result


def save_gray(name, data):
    data = np.clip(data, 0, 255).astype(np.uint8)
    Image.fromarray(data, "L").save(OUT / name, optimize=True)


def save_rgb(name, data):
    Image.fromarray(np.clip(data, 0, 255).astype(np.uint8), "RGB").save(OUT / name, optimize=True)


def normal_from_height(height, strength=3.0):
    h = height.astype(np.float32) / 255
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * strength
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * strength
    nx, ny, nz = -dx, -dy, np.ones_like(h)
    norm = np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.stack([(nx / norm + 1) * 127.5, (ny / norm + 1) * 127.5, (nz / norm + 1) * 127.5], axis=-1)
    return np.clip(rgb, 0, 255).astype(np.uint8)


def create(name, base, seed, roughness, strength=3.0, style="noise"):
    noise = periodic_noise(seed)
    h = np.full((N, N), 126.0, dtype=np.float32)
    if style == "brick":
        h[:] = 62
        for row in range(8):
            y0 = row * 64
            offset = 64 if row % 2 else 0
            for col in range(4):
                x0 = (col * 128 + offset) % N
                xs = np.arange(N)
                ys = np.arange(N)
                # face and bevel relief, with repeating staggered masonry
                for dy in range(3):
                    yy = (y0 + dy) % N
                    h[yy, :] = 34
                h[(y0 + 4) % N:(y0 + 59) % N if (y0 + 59) % N > (y0 + 4) % N else N, :] = h[(y0 + 4) % N:(y0 + 59) % N if (y0 + 59) % N > (y0 + 4) % N else N, :]
                for edge in range(3):
                    x = (x0 + edge) % N
                    h[:, x] = 35
        h += noise * 15
    elif style in ("tile", "roof"):
        h[:] = 118 + noise * 10
        step = 128 if style == "tile" else 64
        for k in range(0, N, step):
            h[k:k+3, :] = 62
            h[:, k:k+3] = 62
        if style == "roof":
            for k in range(0, N, 16):
                h[:, k:k+2] += 16
    elif style == "glass":
        h[:] = 145 + noise * 4
        for k in range(0, N, 128):
            h[k:k+5, :] = 48
            h[:, k:k+5] = 48
        # tileable diagonal reflections
        h += (np.sin((X + Y) * 2 * np.pi / 160) > 0.94) * 22
    elif style == "metal":
        h[:] = 128 + (noise - .5) * 16
        h += (np.sin(X * 2 * np.pi / 128) > .97) * 20
    else:
        h[:] = 120 + (noise - .5) * (76 if style == "asphalt" else 44)
    h = np.clip(h, 0, 255).astype(np.uint8)
    variations = (h.astype(np.float32) - 126) * (0.38 if style == "asphalt" else 0.32)
    rgb = np.zeros((N, N, 3), dtype=np.float32)
    for channel in range(3):
        rgb[:, :, channel] = base[channel] + variations
    save_rgb(f"{name}_albedo.png", rgb)
    Image.fromarray(normal_from_height(h, strength), "RGB").save(OUT / f"{name}_normal.png", optimize=True)
    rmap = np.full((N, N), roughness, dtype=np.float32) + (noise - .5) * 26
    if style == "glass":
        rmap -= (np.sin((X + Y) * 2 * np.pi / 160) > 0.94) * 20
    save_gray(f"{name}_roughness.png", rmap)


OUT.mkdir(parents=True, exist_ok=True)
create("asphalt", (119, 124, 132), 11, 222, 4.5, "asphalt")
create("road_dark", (73, 79, 88), 12, 232, 4.0, "asphalt")
create("concrete", (151, 154, 151), 21, 202, 3.0, "concrete")
create("brick", (133, 107, 96), 31, 224, 4.2, "brick")
create("metal", (139, 151, 163), 41, 132, 1.4, "metal")
create("sidewalk", (160, 160, 151), 51, 212, 1.5, "tile")
create("roof", (92, 103, 113), 61, 220, 3.0, "roof")
create("glass", (64, 104, 134), 71, 52, 0.7, "glass")
create("paint", (157, 164, 171), 81, 78, 0.5, "noise")
print(f"Generated {len(list(OUT.glob('*.png')))} maps in {OUT}")
