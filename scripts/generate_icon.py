#!/usr/bin/env python3
"""Generate AppIcon.icns for Container Manager."""

import os
import subprocess
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("Installing Pillow...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "Pillow"])
    from PIL import Image, ImageDraw, ImageFont


def draw_icon(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    margin = size * 0.04
    r = size * 0.18

    # Background with rounded rect
    draw.rounded_rectangle(
        [margin, margin, size - margin, size - margin],
        radius=r,
        fill=(15, 17, 23),
    )

    # Inner gradient-like layers
    inner_m = size * 0.08
    draw.rounded_rectangle(
        [inner_m, inner_m, size - inner_m, size - inner_m],
        radius=r * 0.85,
        fill=(26, 29, 39),
    )

    # Container box shape
    cx, cy = size / 2, size * 0.42
    bw, bh = size * 0.42, size * 0.28
    box_color = (108, 138, 255)

    # Box top face (parallelogram)
    top_offset = size * 0.08
    top_points = [
        (cx, cy - bh / 2 - top_offset),
        (cx + bw / 2, cy - bh / 2 + top_offset * 0.3),
        (cx, cy - bh / 2 + top_offset * 1.5),
        (cx - bw / 2, cy - bh / 2 + top_offset * 0.3),
    ]
    draw.polygon(top_points, fill=(130, 160, 255))

    # Box front-left face
    left_points = [
        (cx - bw / 2, cy - bh / 2 + top_offset * 0.3),
        (cx, cy - bh / 2 + top_offset * 1.5),
        (cx, cy + bh / 2),
        (cx - bw / 2, cy + bh / 2 - top_offset * 1.2),
    ]
    draw.polygon(left_points, fill=(80, 110, 220))

    # Box front-right face
    right_points = [
        (cx + bw / 2, cy - bh / 2 + top_offset * 0.3),
        (cx, cy - bh / 2 + top_offset * 1.5),
        (cx, cy + bh / 2),
        (cx + bw / 2, cy + bh / 2 - top_offset * 1.2),
    ]
    draw.polygon(right_points, fill=(58, 88, 200))

    # "RT" text below the box
    text_y = size * 0.68
    font_size = int(size * 0.18)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/SFCompact.ttf", font_size)
    except (OSError, IOError):
        try:
            font = ImageFont.truetype(
                "/System/Library/Fonts/Supplemental/Arial Bold.ttf", font_size
            )
        except (OSError, IOError):
            font = ImageFont.load_default()

    text = "CM"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    draw.text(
        (cx - tw / 2, text_y),
        text,
        fill=(108, 138, 255),
        font=font,
    )

    # Small "inform" text
    small_size = int(size * 0.07)
    try:
        small_font = ImageFont.truetype(
            "/System/Library/Fonts/SFCompact.ttf", small_size
        )
    except (OSError, IOError):
        try:
            small_font = ImageFont.truetype(
                "/System/Library/Fonts/Supplemental/Arial.ttf", small_size
            )
        except (OSError, IOError):
            small_font = ImageFont.load_default()

    sub_text = "compose"
    sub_bbox = draw.textbbox((0, 0), sub_text, font=small_font)
    sub_tw = sub_bbox[2] - sub_bbox[0]
    draw.text(
        (cx - sub_tw / 2, text_y + font_size * 0.95),
        sub_text,
        fill=(139, 143, 163),
        font=small_font,
    )

    return img


def main():
    project_root = Path(__file__).parent.parent
    iconset_dir = project_root / "ContainerManagerApp" / "AppIcon.iconset"
    iconset_dir.mkdir(parents=True, exist_ok=True)

    sizes = [
        (16, 1), (16, 2),
        (32, 1), (32, 2),
        (128, 1), (128, 2),
        (256, 1), (256, 2),
        (512, 1), (512, 2),
    ]

    for base_size, scale in sizes:
        px = base_size * scale
        icon = draw_icon(px)
        suffix = f"@2x" if scale == 2 else ""
        filename = f"icon_{base_size}x{base_size}{suffix}.png"
        icon.save(iconset_dir / filename)
        print(f"  Generated {filename} ({px}x{px})")

    icns_path = project_root / "ContainerManagerApp" / "Resources" / "AppIcon.icns"
    icns_path.parent.mkdir(parents=True, exist_ok=True)

    result = subprocess.run(
        ["iconutil", "-c", "icns", str(iconset_dir), "-o", str(icns_path)],
        capture_output=True, text=True,
    )

    if result.returncode == 0:
        print(f"  Created {icns_path}")
    else:
        print(f"  iconutil error: {result.stderr}")
        sys.exit(1)

    # Cleanup iconset
    import shutil
    shutil.rmtree(iconset_dir)
    print("Done!")


if __name__ == "__main__":
    main()
