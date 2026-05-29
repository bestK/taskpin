"""Generate braille spinner animated GIF for taskpin claude_status."""
from PIL import Image, ImageDraw, ImageFont
import struct

FRAMES = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
SIZE = 32
DELAY_MS = 100
COLOR = (217, 119, 87)  # #D97757
OUT = "examples/claude_spinner.gif"

images = []
for ch in FRAMES:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("seguisym.ttf", 24)
    except OSError:
        font = ImageFont.load_default()
    bbox = draw.textbbox((0, 0), ch, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    x = (SIZE - tw) // 2 - bbox[0]
    y = (SIZE - th) // 2 - bbox[1]
    draw.text((x, y), ch, fill=COLOR, font=font)
    images.append(img)

images[0].save(
    OUT,
    save_all=True,
    append_images=images[1:],
    duration=DELAY_MS,
    loop=0,
    disposal=2,
    transparency=0,
)
print(f"Generated {OUT} ({len(images)} frames, {DELAY_MS}ms/frame)")