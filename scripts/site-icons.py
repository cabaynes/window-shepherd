"""Builds the website's icons from the app icon. Run: python3 -I scripts/site-icons.py
Writes site/favicon.ico (16/32/48), site/icon-32.png, site/apple-touch-icon.png (180, on white),
and site/tests/.shots/og-icon.png (512, used by site/tests/og-card.html; not published)."""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "App/WindowShepherd/Assets.xcassets/AppIcon.appiconset"
SITE = ROOT / "site"

def icon(name):
    return Image.open(SRC / name).convert("RGBA")

# ICO: each size from the app's own natively drawn PNG where one exists; Pillow keeps only
# sizes no larger than the base image, so the 48 px is the base and the others are appended.
i16, i32 = icon("icon_16.png"), icon("icon_32.png")
i48 = icon("icon_64.png").resize((48, 48), Image.LANCZOS)
i48.save(SITE / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)], append_images=[i32, i16])
i32.save(SITE / "icon-32.png")

touch = Image.new("RGBA", (180, 180), "white")   # iOS fills transparency with black
touch.alpha_composite(icon("icon_256.png").resize((180, 180), Image.LANCZOS))
touch.convert("RGB").save(SITE / "apple-touch-icon.png")

shots = SITE / "tests/.shots"
shots.mkdir(parents=True, exist_ok=True)
icon("icon_512.png").save(shots / "og-icon.png")
print("icons written")
