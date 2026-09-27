#!/usr/bin/env python3
"""Vẽ hình nền aero-sky.jpg: nền xanh chuyển màu, vài dải sáng uốn lượn
và đốm sáng mờ kiểu Aero. Hình tự tạo hoàn toàn bằng code nên không dính
bản quyền của ai.

Cần: python3, numpy, pillow.
    python3 wallpapers/make-aero.py            # ghi wallpapers/aero-sky.jpg
    python3 wallpapers/make-aero.py out.jpg 2560 1440
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

SEED = 7


def hex_rgb(value: str) -> np.ndarray:
    value = value.lstrip("#")
    return np.array([int(value[i : i + 2], 16) for i in (0, 2, 4)], dtype=np.float32) / 255.0


def vertical_gradient(h: int, w: int, stops: list[tuple[float, str]]) -> np.ndarray:
    ys = np.linspace(0.0, 1.0, h, dtype=np.float32)
    positions = np.array([p for p, _ in stops], dtype=np.float32)
    colors = np.stack([hex_rgb(c) for _, c in stops])
    column = np.stack([np.interp(ys, positions, colors[:, ch]) for ch in range(3)], axis=-1)
    return np.repeat(column[:, None, :], w, axis=1)


def ribbon(xx, yy, center, amplitude, frequency, phase, width, tilt):
    """Dải sáng mềm chạy ngang màn hình theo một đường sin."""
    path = center + tilt * (xx - 0.5) + amplitude * np.sin(frequency * xx * np.pi * 2 + phase)
    distance = np.abs(yy - path)
    core = np.exp(-((distance / width) ** 2))
    halo = np.exp(-((distance / (width * 4)) ** 2)) * 0.35
    return core + halo


def render(width: int, height: int) -> Image.Image:
    rng = np.random.default_rng(SEED)
    aspect = width / height

    image = vertical_gradient(
        height,
        width,
        [(0.0, "#061a3a"), (0.45, "#0f4c9c"), (0.8, "#2f8ae6"), (1.0, "#7cc4ff")],
    )

    yy, xx = np.mgrid[0:height, 0:width].astype(np.float32)
    yy /= height
    xx /= width

    # Ánh sáng tỏa từ góc trên phải.
    glow = np.exp(-(((xx - 0.8) * aspect) ** 2 + (yy - 0.15) ** 2) / 0.18)
    image += glow[..., None] * hex_rgb("#3f8fe0") * 0.35

    # Các dải sáng.
    light = np.zeros((height, width), dtype=np.float32)
    light += ribbon(xx, yy, 0.62, 0.07, 0.8, 0.4, 0.010, -0.18) * 0.55
    light += ribbon(xx, yy, 0.70, 0.05, 1.1, 1.9, 0.006, -0.22) * 0.45
    light += ribbon(xx, yy, 0.55, 0.09, 0.6, 3.1, 0.018, -0.12) * 0.30
    image += light[..., None] * hex_rgb("#bfe6ff")

    # Đốm sáng: vẽ trên lớp riêng rồi làm mờ.
    bokeh = Image.new("L", (width, height), 0)
    pixels = np.zeros((height, width), dtype=np.float32)
    for _ in range(38):
        cx = rng.uniform(0.35, 1.0) * width
        cy = rng.uniform(0.35, 0.95) * height
        radius = rng.uniform(0.006, 0.03) * width
        strength = rng.uniform(0.15, 0.5)
        mask = ((np.arange(width)[None, :] - cx) ** 2 + (np.arange(height)[:, None] - cy) ** 2) <= radius**2
        pixels[mask] = np.maximum(pixels[mask], strength)
    bokeh = Image.fromarray((pixels * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(width / 400))
    bokeh_layer = np.asarray(bokeh, dtype=np.float32) / 255.0
    image += bokeh_layer[..., None] * hex_rgb("#d8f0ff") * 0.6

    # Nhiễu nhẹ để chuyển màu không bị sọc.
    image += rng.normal(0.0, 0.006, size=image.shape).astype(np.float32)

    image = np.clip(image, 0.0, 1.0)
    return Image.fromarray((image * 255).astype(np.uint8), "RGB")


def main() -> None:
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).with_name("aero-sky.jpg")
    width = int(sys.argv[2]) if len(sys.argv) > 2 else 3840
    height = int(sys.argv[3]) if len(sys.argv) > 3 else 2160
    render(width, height).save(out, quality=90, optimize=True, progressive=True)
    print(f"đã ghi {out} ({width}x{height})")


if __name__ == "__main__":
    main()
