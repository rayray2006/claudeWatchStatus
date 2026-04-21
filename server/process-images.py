#!/usr/bin/env python3
"""
Convert ClaudeTap pixel art JPGs to PNGs with transparent backgrounds.
Black pixels become transparent, light pixels become white.
This lets watchOS tint the character silhouette with the watch face accent color.
"""
from PIL import Image
import os

ASSETS = "/Users/rayray/Documents/Code/ClaudeTap/ClaudeTapWatch/Assets.xcassets"

names = ["ClaudeIdle", "ClaudeWorking", "ClaudeDone", "ClaudeApproval"]

for name in names:
    imageset = f"{ASSETS}/{name}.imageset"
    # Find the source jpg
    jpg = None
    for f in os.listdir(imageset):
        if f.endswith(".jpg"):
            jpg = f"{imageset}/{f}"
            break
    if not jpg:
        print(f"No JPG found in {imageset}")
        continue

    img = Image.open(jpg).convert("RGBA")
    pixels = img.load()
    w, h = img.size

    # Make dark pixels transparent, keep brightness for tinting
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            brightness = (r + g + b) // 3
            if brightness < 30:  # Very dark = transparent
                pixels[x, y] = (0, 0, 0, 0)
            else:
                # Keep as bright white so tint shows full opacity
                pixels[x, y] = (255, 255, 255, brightness)

    out = jpg.replace(".jpg", ".png")
    img.save(out, "PNG")
    print(f"✓ {name} → {out}")

    # Update Contents.json to point to PNG
    contents_path = f"{imageset}/Contents.json"
    with open(contents_path, "r") as f:
        contents = f.read()
    contents = contents.replace(".jpg", ".png")
    with open(contents_path, "w") as f:
        f.write(contents)
    # Remove old jpg
    os.remove(jpg)
    print(f"  Updated Contents.json, removed JPG")
