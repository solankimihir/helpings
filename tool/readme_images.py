"""Builds the images the README and GitHub use, from the store assets.

    python3 -m pip install pillow   # once
    python3 tool/readme_images.py

Writes to docs/readme/:
  logo.png             the app icon with rounded corners
  screens/*.png        store screenshots, smaller, with rounded corners
  social-preview.png   1280x640 card for GitHub's "Social preview" setting

Run it again after regenerating the store screenshots.
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / "android/fastlane/metadata/android/en-US/images"
OUT = ROOT / "docs/readme"
BG = (247, 245, 240)  # app background, light theme


def rounded(img: Image.Image, radius: int) -> Image.Image:
    """[img] with transparent rounded corners, drawn at 4x for smooth edges."""
    img = img.convert("RGBA")
    scale = 4
    mask = Image.new("L", (img.width * scale, img.height * scale), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, mask.width - 1, mask.height - 1), radius * scale, fill=255
    )
    mask = mask.resize(img.size, Image.LANCZOS)
    img.putalpha(mask)
    return img


def main() -> None:
    (OUT / "screens").mkdir(parents=True, exist_ok=True)

    icon = Image.open(ROOT / "assets/icon/icon.png").resize((256, 256), Image.LANCZOS)
    rounded(icon, 58).save(OUT / "logo.png", optimize=True)

    for src in sorted((STORE / "phoneScreenshots").glob("*.png")):
        shot = Image.open(src)
        w = 540
        shot = shot.resize((w, round(shot.height * w / shot.width)), Image.LANCZOS)
        rounded(shot, 36).save(OUT / "screens" / src.name, optimize=True)

    # Feature graphic (1024x500) filling a 1280x640 card.
    feature = Image.open(STORE / "featureGraphic.png").convert("RGB")
    h = 640
    w = round(feature.width * h / feature.height)
    feature = feature.resize((w, h), Image.LANCZOS)
    card = Image.new("RGB", (1280, 640), BG)
    card.paste(feature, ((1280 - w) // 2, 0))
    card.save(OUT / "social-preview.png", optimize=True)


if __name__ == "__main__":
    main()
