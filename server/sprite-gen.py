#!/usr/bin/env python3
"""
Convert pixel art images into Swift Canvas-based sprite views.
Uses palette + base64 encoding so the compiler doesn't choke on big literal
arrays. Preserves the full source image (no content-bbox cropping).
"""
from PIL import Image
import base64
import os

ASSETS = "/Users/rayray/Documents/Code/ClaudeTap/ClaudeTapWatch/Assets.xcassets"
OUT = "/Users/rayray/Documents/Code/ClaudeTap/Shared/ClaudeSprites.swift"
GRID = 512  # render grid resolution — base64 keeps Swift compile fast

states = {
    "idle": "ClaudeIdle",
    "working": "ClaudeWorking",
    "done": "ClaudeDone",
    "approval": "ClaudeApproval",
}

def pad_to_square(image_path):
    """Load the image and pad to a square canvas. No cropping."""
    img = Image.open(image_path).convert("RGBA")
    w, h = img.size
    side = max(w, h)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.paste(img, ((side - w) // 2, (side - h) // 2))
    return square

def encode_sprite(image_path, grid):
    """Returns (palette, base64_pixel_data). Palette index 0 is always transparent."""
    img = pad_to_square(image_path)
    # NEAREST keeps pixel art edges crisp, no interpolation bleed.
    img = img.resize((grid, grid), Image.NEAREST)

    rgb = img.convert("RGB")
    alpha = img.split()[-1]

    # Use real alpha if present; otherwise treat near-white as transparent
    # (these input images are RGB-on-white pixel art with no alpha channel).
    alpha_vals = list(alpha.getdata())
    has_real_alpha = any(a < 250 for a in alpha_vals)

    quantized = rgb.quantize(colors=255, method=Image.Quantize.MEDIANCUT)
    pal = quantized.getpalette()

    palette = [(0, 0, 0, 0)]
    for i in range(255):
        palette.append((pal[i*3], pal[i*3+1], pal[i*3+2], 255))

    qpixels = quantized.load()
    alpha_pixels = alpha.load()
    rgb_pixels = rgb.load()

    indices = bytearray()
    for y in range(grid):
        for x in range(grid):
            a = alpha_pixels[x, y]
            r, g, b = rgb_pixels[x, y]
            if has_real_alpha:
                is_transparent = a < 128
            else:
                # Near-white → transparent. Threshold high enough to preserve
                # light shades in the character but erase the background.
                is_transparent = min(r, g, b) >= 245

            indices.append(0 if is_transparent else qpixels[x, y] + 1)

    return palette, base64.b64encode(bytes(indices)).decode("ascii")


# Generate Swift
lines = []
lines.append("import SwiftUI")
lines.append("")
lines.append(f"/// High-resolution pixel art sprites ({GRID}x{GRID}). Palette + base64 encoded.")
lines.append("struct ClaudeSpriteView: View {")
lines.append("    let state: TapState")
lines.append("")
lines.append("    var body: some View {")
lines.append("        staticSprite")
lines.append("    }")
lines.append("")
lines.append("    private var staticSprite: some View {")
lines.append(f"        Canvas {{ ctx, size in")
lines.append(f"            let grid = {GRID}")
lines.append("            let data = pixelBytes(for: state)")
lines.append("            let palette = paletteFor(state: state)")
lines.append("            guard !data.isEmpty else { return }")
lines.append("            let w = size.width / CGFloat(grid)")
lines.append("            let h = size.height / CGFloat(grid)")
lines.append("            for y in 0..<grid {")
lines.append("                for x in 0..<grid {")
lines.append("                    let idx = Int(data[y * grid + x])")
lines.append("                    if idx == 0 { continue }")
lines.append("                    let c = palette[idx]")
lines.append("                    let rect = CGRect(x: CGFloat(x) * w, y: CGFloat(y) * h, width: w + 0.5, height: h + 0.5)")
lines.append("                    ctx.fill(Path(rect), with: .color(Color(red: c.r, green: c.g, blue: c.b)))")
lines.append("                }")
lines.append("            }")
lines.append("        }")
lines.append("    }")
lines.append("")
lines.append("    private func pixelBytes(for state: TapState) -> [UInt8] {")
lines.append("        let b64: String")
lines.append("        switch state {")
for key in states:
    lines.append(f"        case .{key if key != 'approval' else 'needsApproval'}: b64 = Self.data_{key}")
lines.append("        }")
lines.append("        return Array(Data(base64Encoded: b64) ?? Data())")
lines.append("    }")
lines.append("")
lines.append("    private func paletteFor(state: TapState) -> [Pixel] {")
lines.append("        switch state {")
for key in states:
    lines.append(f"        case .{key if key != 'approval' else 'needsApproval'}: return Self.palette_{key}")
lines.append("        }")
lines.append("    }")
lines.append("")
lines.append("    typealias Pixel = (r: Double, g: Double, b: Double)")
lines.append("")

for key, name in states.items():
    imageset = f"{ASSETS}/{name}.imageset"
    source = None
    for f in os.listdir(imageset):
        if f.endswith(".png") or f.endswith(".jpg"):
            source = f"{imageset}/{f}"
            break
    if not source:
        print(f"⚠ No image for {name}, skipping")
        continue

    palette, b64 = encode_sprite(source, GRID)

    lines.append(f"    static let palette_{key}: [Pixel] = [")
    for r, g, b, _ in palette:
        lines.append(f"        (r: {r/255:.3f}, g: {g/255:.3f}, b: {b/255:.3f}),")
    lines.append("    ]")
    lines.append("")
    lines.append(f"    static let data_{key}: String = \"{b64}\"")
    lines.append("")
    print(f"✓ {name}: {len(palette)} colors, {len(b64)} chars of data")

lines.append("}")

with open(OUT, "w") as f:
    f.write("\n".join(lines))

print(f"\n✓ Generated: {OUT}")
