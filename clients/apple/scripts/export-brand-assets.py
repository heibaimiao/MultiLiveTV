#!/usr/bin/env python3
"""Crop MultiLiveTV brand-sheet art into App Icon / Logo / tvOS shelf assets."""

from __future__ import annotations

import json
import sys
from collections import deque
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("Need Pillow: python3 -m pip install pillow")

ROOT = Path(__file__).resolve().parents[1]
SHEET = ROOT / "brand" / "logo-sheet.jpg"
ASSETS = ROOT / "MultiLiveTV" / "Assets.xcassets"

NAVY = (2, 17, 48)
INFO = {"author": "xcode", "version": 1}


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n")


def near_white(pixel: tuple[int, ...]) -> bool:
    r, g, b = pixel[:3]
    brightness = (r + g + b) / 3
    saturation = max(r, g, b) - min(r, g, b)
    return brightness > 180 and saturation < 40


def near_navy(pixel: tuple[int, ...]) -> bool:
    r, g, b = pixel[:3]
    brightness = (r + g + b) / 3
    saturation = max(r, g, b) - min(r, g, b)
    return abs(r - NAVY[0]) + abs(g - NAVY[1]) + abs(b - NAVY[2]) < 36 and saturation < 50 and brightness < 70


def flood(pixels, width: int, height: int, starts: list[tuple[int, int]], match, paint) -> None:
    queue = deque(starts)
    seen: set[tuple[int, int]] = set()
    while queue:
        x, y = queue.popleft()
        if (x, y) in seen or not (0 <= x < width and 0 <= y < height):
            continue
        seen.add((x, y))
        if not match(pixels[x, y]):
            continue
        paint(x, y)
        queue.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))


def find_dark_icon_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    """Walk the filled navy rounded-square from its widest bar, ignoring the light tile."""
    width, height = image.size
    pixels = image.load()
    x_min = int(width * 0.55)
    rows: list[list[int]] = []
    for y in range(height):
        rows.append([x for x in range(x_min, width) if near_navy(pixels[x, y])])

    best_y = max(range(height), key=lambda y: len(rows[y]))
    if len(rows[best_y]) < 80:
        raise RuntimeError("Could not locate the dark app-icon tile on the brand sheet")

    xs = rows[best_y]
    runs: list[tuple[int, int]] = []
    start = prev = xs[0]
    for x in xs[1:]:
        if x <= prev + 2:
            prev = x
        else:
            runs.append((start, prev))
            start = prev = x
    runs.append((start, prev))
    x0, x1 = max(runs, key=lambda run: run[1] - run[0])

    def row_on_tile(y: int) -> bool:
        return sum(1 for x in rows[y] if x0 - 10 <= x <= x1 + 10) >= 8

    y0 = best_y
    while y0 > 0 and row_on_tile(y0 - 1):
        y0 -= 1
    y1 = best_y
    while y1 < height - 1 and row_on_tile(y1 + 1):
        y1 += 1

    xs = [x for y in range(y0, y1 + 1) for x in rows[y] if x0 - 10 <= x <= x1 + 10]
    pad = 6
    return (
        max(0, min(xs) - pad),
        max(0, y0 - pad),
        min(width, max(xs) + pad + 1),
        min(height, y1 + pad + 1),
    )


def extract_dark_tile(sheet: Image.Image) -> Image.Image:
    x0, y0, x1, y1 = find_dark_icon_bbox(sheet)
    tile = sheet.crop((x0, y0, x1, y1)).convert("RGBA")
    pixels = tile.load()
    width, height = tile.size

    def paint_navy(x: int, y: int) -> None:
        pixels[x, y] = (*NAVY, 255)

    flood(
        pixels,
        width,
        height,
        [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)],
        near_white,
        paint_navy,
    )
    return tile


def opaque_square_icon(tile: Image.Image, size: int) -> Image.Image:
    rgb = tile.convert("RGB")
    side = max(rgb.size)
    square = Image.new("RGB", (side, side), NAVY)
    square.paste(rgb, ((side - rgb.size[0]) // 2, (side - rgb.size[1]) // 2))
    return square.resize((size, size), Image.Resampling.LANCZOS)


def transparent_mark(tile: Image.Image) -> Image.Image:
    mark = tile.copy()
    pixels = mark.load()
    width, height = mark.size

    def paint_clear(x: int, y: int) -> None:
        pixels[x, y] = (0, 0, 0, 0)

    starts = [(x, 0) for x in range(width)] + [(x, height - 1) for x in range(width)]
    starts += [(0, y) for y in range(height)] + [(width - 1, y) for y in range(height)]
    flood(pixels, width, height, starts, near_navy, paint_clear)
    for y in range(height):
        for x in range(width):
            if near_navy(pixels[x, y]):
                pixels[x, y] = (0, 0, 0, 0)
    bbox = mark.getbbox()
    if bbox is None:
        raise RuntimeError("Transparent logo mark is empty")
    return mark.crop(bbox)


def fit_mark(mark: Image.Image, canvas: tuple[int, int], max_ratio: float = 0.72) -> Image.Image:
    max_h = int(canvas[1] * max_ratio)
    max_w = int(canvas[0] * max_ratio)
    scale = min(max_w / mark.size[0], max_h / mark.size[1])
    size = (max(1, int(mark.size[0] * scale)), max(1, int(mark.size[1] * scale)))
    return mark.resize(size, Image.Resampling.LANCZOS)


def compose_opaque(mark: Image.Image, size: tuple[int, int], left_bias: bool = False) -> Image.Image:
    canvas = Image.new("RGB", size, NAVY)
    fitted = fit_mark(mark, size)
    if left_bias:
        x = int(size[0] * 0.08)
        y = (size[1] - fitted.size[1]) // 2
    else:
        x = (size[0] - fitted.size[0]) // 2
        y = (size[1] - fitted.size[1]) // 2
    canvas.paste(fitted, (x, y), fitted)
    return canvas


def compose_front(mark: Image.Image, size: tuple[int, int]) -> Image.Image:
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    fitted = fit_mark(mark, size)
    canvas.paste(fitted, ((size[0] - fitted.size[0]) // 2, (size[1] - fitted.size[1]) // 2), fitted)
    return canvas


def solid(size: tuple[int, int]) -> Image.Image:
    return Image.new("RGB", size, NAVY)


def write_imageset(folder: Path, filename: str, idiom: str, extra: dict | None = None) -> None:
    image = {"filename": filename, "idiom": idiom}
    if extra:
        image.update(extra)
    write_json(folder / "Contents.json", {"images": [image], "info": INFO})


def write_layer(stack: Path, name: str, image: Image.Image, filename: str, extra: dict | None = None) -> None:
    layer = stack / f"{name}.imagestacklayer"
    content = layer / "Content.imageset"
    content.mkdir(parents=True, exist_ok=True)
    write_json(layer / "Contents.json", {"info": INFO})
    image.save(content / filename)
    write_imageset(content, filename, "tv", extra)


def write_imagestack(brand: Path, name: str, front: Image.Image, back: Image.Image, filename: str, extra: dict | None = None) -> None:
    stack = brand / f"{name}.imagestack"
    write_json(
        stack / "Contents.json",
        {
            "info": INFO,
            "layers": [
                {"filename": "Front.imagestacklayer"},
                {"filename": "Middle.imagestacklayer"},
                {"filename": "Back.imagestacklayer"},
            ],
        },
    )
    write_layer(stack, "Front", front, filename, extra)
    write_layer(stack, "Middle", back, f"Middle-{filename}", extra)
    write_layer(stack, "Back", back, f"Back-{filename}", extra)


def export() -> None:
    if not SHEET.exists():
        sys.exit(f"Missing brand sheet: {SHEET}")

    sheet = Image.open(SHEET).convert("RGB")
    tile = extract_dark_tile(sheet)
    mark = transparent_mark(tile)
    app_icon = opaque_square_icon(tile, 1024)

    ASSETS.mkdir(parents=True, exist_ok=True)
    write_json(ASSETS / "Contents.json", {"info": INFO})

    appicon_set = ASSETS / "AppIcon.appiconset"
    appicon_set.mkdir(parents=True, exist_ok=True)
    app_icon.save(appicon_set / "AppIcon.png")
    write_json(
        appicon_set / "Contents.json",
        {
            "images": [
                {
                    "filename": "AppIcon.png",
                    "idiom": "universal",
                    "platform": "ios",
                    "size": "1024x1024",
                }
            ],
            "info": INFO,
        },
    )

    logo_set = ASSETS / "Logo.imageset"
    logo_set.mkdir(parents=True, exist_ok=True)
    logo = mark.copy()
    longest = max(logo.size)
    scale = 512 / longest
    logo = logo.resize(
        (max(1, int(logo.size[0] * scale)), max(1, int(logo.size[1] * scale))),
        Image.Resampling.LANCZOS,
    )
    logo.save(logo_set / "Logo.png")
    write_json(
        logo_set / "Contents.json",
        {
            "images": [{"filename": "Logo.png", "idiom": "universal"}],
            "info": INFO,
            "properties": {"template-rendering-intent": "original"},
        },
    )

    write_json(
        ASSETS / "LaunchBackground.colorset" / "Contents.json",
        {
            "colors": [
                {
                    "color": {
                        "color-space": "srgb",
                        "components": {
                            "alpha": "1.000",
                            "red": "0.055",
                            "green": "0.055",
                            "blue": "0.062",
                        },
                    },
                    "idiom": "universal",
                }
            ],
            "info": INFO,
        },
    )

    brand = ASSETS / "App Icon & Top Shelf Image.brandassets"
    write_json(
        brand / "Contents.json",
        {
            "assets": [
                {
                    "filename": "App Icon.imagestack",
                    "idiom": "tv",
                    "role": "primary-app-icon",
                    "size": "400x240",
                },
                {
                    "filename": "App Icon - App Store.imagestack",
                    "idiom": "tv",
                    "role": "primary-app-icon",
                    "size": "1280x768",
                },
                {
                    "filename": "Top Shelf Image.imageset",
                    "idiom": "tv",
                    "role": "top-shelf-image",
                    "size": "1920x720",
                },
                {
                    "filename": "Top Shelf Image Wide.imageset",
                    "idiom": "tv",
                    "role": "top-shelf-image-wide",
                    "size": "2320x720",
                },
            ],
            "info": INFO,
        },
    )

    write_imagestack(
        brand,
        "App Icon",
        compose_front(mark, (400, 240)),
        solid((400, 240)),
        "Front.png",
        {"scale": "1x"},
    )
    front2x = brand / "App Icon.imagestack" / "Front.imagestacklayer" / "Content.imageset"
    middle2x = brand / "App Icon.imagestack" / "Middle.imagestacklayer" / "Content.imageset"
    back2x = brand / "App Icon.imagestack" / "Back.imagestacklayer" / "Content.imageset"
    compose_front(mark, (800, 480)).save(front2x / "Front@2x.png")
    solid((800, 480)).save(middle2x / "Middle@2x.png")
    solid((800, 480)).save(back2x / "Back@2x.png")
    for folder, one, two in (
        (front2x, "Front.png", "Front@2x.png"),
        (middle2x, "Middle-Front.png", "Middle@2x.png"),
        (back2x, "Back-Front.png", "Back@2x.png"),
    ):
        write_json(
            folder / "Contents.json",
            {
                "images": [
                    {"filename": one, "idiom": "tv", "scale": "1x"},
                    {"filename": two, "idiom": "tv", "scale": "2x"},
                ],
                "info": INFO,
            },
        )

    write_imagestack(
        brand,
        "App Icon - App Store",
        compose_front(mark, (1280, 768)),
        solid((1280, 768)),
        "Front.png",
        {"scale": "1x"},
    )

    shelf = solid((1920, 720))
    wide = solid((2320, 720))
    shelf_set = brand / "Top Shelf Image.imageset"
    wide_set = brand / "Top Shelf Image Wide.imageset"
    shelf_set.mkdir(parents=True, exist_ok=True)
    wide_set.mkdir(parents=True, exist_ok=True)
    shelf.save(shelf_set / "TopShelf.png")
    wide.save(wide_set / "TopShelfWide.png")
    write_imageset(shelf_set, "TopShelf.png", "tv", {"scale": "1x"})
    write_imageset(wide_set, "TopShelfWide.png", "tv", {"scale": "1x"})

    print(f"dark tile bbox {find_dark_icon_bbox(sheet)}")
    print(f"AppIcon {app_icon.size} {app_icon.mode}")
    print(f"Logo {logo.size} {logo.mode}")
    print(f"wrote {ASSETS}")


if __name__ == "__main__":
    export()
