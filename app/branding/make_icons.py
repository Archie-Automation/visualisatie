"""Build full-bleed Archie OS launcher icons (no baked squircle / white fringe)."""

from __future__ import annotations

from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
BRANDING = Path(__file__).resolve().parent
SRC_CANDIDATES = [
    Path(
        r"C:\Users\gebruiker\.cursor\projects\c-Users-gebruiker-KNX-app\assets"
        r"\c__Users_gebruiker_AppData_Roaming_Cursor_User_workspaceStorage_"
        r"1c2e0bb87d53119989277bfaad862c95_images_archieOS_kopie-4b029a05-4c44-4e9f-9793-6d60f90decf7.png"
    ),
    BRANDING / "app_icon.png",
]


def median_rgb(samples: list[tuple[int, int, int]]) -> tuple[int, int, int]:
    n = len(samples)
    rs = sorted(p[0] for p in samples)
    gs = sorted(p[1] for p in samples)
    bs = sorted(p[2] for p in samples)
    m = n // 2
    return rs[m], gs[m], bs[m]


def sample_fill(im: Image.Image) -> tuple[int, int, int]:
    w, h = im.size
    pix = im.load()
    samples: list[tuple[int, int, int]] = []
    for y in range(int(h * 0.18), int(h * 0.38)):
        for x in range(int(w * 0.18), int(w * 0.38)):
            r, g, b, a = pix[x, y]
            if a < 200:
                continue
            mx, mn = max(r, g, b), min(r, g, b)
            if mx < 70 and (mx - mn) < 30:
                samples.append((r, g, b))
    if len(samples) < 50:
        return (48, 43, 37)
    return median_rgb(samples)


def full_bleed(src: Image.Image) -> tuple[Image.Image, tuple[int, int, int]]:
    """Replace corner/fringe/baked-bezel pixels with interior charcoal."""
    im = src.convert("RGBA")
    w, h = im.size
    pix = im.load()
    fill = sample_fill(im)
    fr, fg, fb = fill

    def dist_fill(r: int, g: int, b: int) -> int:
        return abs(r - fr) + abs(g - fg) + abs(b - fb)

    def can_flood(x: int, y: int) -> bool:
        r, g, b, a = pix[x, y]
        if a < 240:
            return True
        return dist_fill(r, g, b) >= 30

    seen = bytearray(w * h)
    q: deque[tuple[int, int]] = deque()
    for x, y in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        q.append((x, y))
        seen[y * w + x] = 1

    outside = bytearray(w * h)
    while q:
        x, y = q.popleft()
        if not can_flood(x, y):
            continue
        outside[y * w + x] = 255
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if nx < 0 or ny < 0 or nx >= w or ny >= h:
                continue
            i = ny * w + nx
            if seen[i]:
                continue
            seen[i] = 1
            q.append((nx, ny))

    mask = Image.frombytes("L", (w, h), bytes(outside))
    # Eat the light gold/white outer bezel so launcher masks don't show a halo.
    mask = mask.filter(ImageFilter.MaxFilter(17))
    mp = mask.load()
    out = Image.new("RGB", (w, h), fill)
    dest = out.load()
    for y in range(h):
        for x in range(w):
            if mp[x, y] < 128:
                r, g, b, a = pix[x, y]
                if a >= 250:
                    dest[x, y] = (r, g, b)
                else:
                    t = a / 255.0
                    dest[x, y] = (
                        round(r * t + fr * (1 - t)),
                        round(g * t + fg * (1 - t)),
                        round(b * t + fb * (1 - t)),
                    )
    return out, fill


def resize(im: Image.Image, size: int) -> Image.Image:
    return im.resize((size, size), Image.Resampling.LANCZOS)


def save_png(im: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp.png")
    im.save(tmp, "PNG", optimize=True)
    tmp.replace(path)
    print(f"  {path.relative_to(ROOT)}  {im.size[0]}px  {path.stat().st_size}b")


def padded(
    im: Image.Image, size: int, fill: tuple[int, int, int], pad_ratio: float = 0.10
) -> Image.Image:
    inner = max(1, int(round(size * (1 - 2 * pad_ratio))))
    canvas = Image.new("RGB", (size, size), fill)
    icon = resize(im, inner)
    off = (size - inner) // 2
    canvas.paste(icon, (off, off))
    return canvas


def main() -> None:
    src_path = next(p for p in SRC_CANDIDATES if p.exists())
    print(f"source: {src_path}")
    bleed, fill = full_bleed(Image.open(src_path))
    print(f"fill: rgb{fill}")

    master = resize(bleed, 1024)
    try:
        save_png(master, BRANDING / "app_icon.png")
    except OSError as err:
        alt = BRANDING / "app_icon_full.png"
        print(f"skip branding/app_icon.png ({err}); writing {alt.name}")
        save_png(master, alt)
    save_png(resize(bleed, 512), ROOT / "assets" / "images" / "app_icon.png")

    mip = {
        "mdpi": 48,
        "hdpi": 72,
        "xhdpi": 96,
        "xxhdpi": 144,
        "xxxhdpi": 192,
    }
    for density, size in mip.items():
        save_png(
            resize(bleed, size),
            ROOT / "android" / "app" / "src" / "main" / "res" / f"mipmap-{density}" / "ic_launcher.png",
        )

    web = ROOT / "web"
    save_png(resize(bleed, 32), web / "favicon.png")
    save_png(resize(bleed, 180), web / "icons" / "Icon-180.png")
    save_png(resize(bleed, 192), web / "icons" / "Icon-192.png")
    save_png(resize(bleed, 512), web / "icons" / "Icon-512.png")
    save_png(padded(bleed, 192, fill, 0.10), web / "icons" / "Icon-maskable-192.png")
    save_png(padded(bleed, 512, fill, 0.10), web / "icons" / "Icon-maskable-512.png")
    save_png(
        padded(bleed, 432, fill, 0.12),
        ROOT / "android" / "app" / "src" / "main" / "res" / "drawable" / "ic_launcher_foreground.png",
    )
    hex_fill = f"#{fill[0]:02X}{fill[1]:02X}{fill[2]:02X}"
    print(f"LAUNCHER_BG={hex_fill}")


if __name__ == "__main__":
    main()
