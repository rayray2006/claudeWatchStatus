#!/usr/bin/env python3
"""
Convert pixel art images into Swift Canvas-based sprite views.
Uses palette + base64 encoding so we can use high resolution
without choking the Swift compiler on huge literal arrays.
"""
from PIL import Image
import base64
import os

ASSETS = "/Users/rayray/Documents/Code/ClaudeTap/ClaudeTapWatch/Assets.xcassets"
OUT = "/Users/rayray/Documents/Code/ClaudeTap/Shared/ClaudeSprites.swift"
GRID = 512  # Very high resolution — base64 keeps compile fast

states = {
    "idle": "ClaudeIdle",
    "working": "ClaudeWorking",
    "done": "ClaudeDone",
    "approval": "ClaudeApproval",
}

def get_content_bbox(img):
    """Find bounding box of non-background content."""
    alpha = img.split()[-1]
    alpha_vals = list(alpha.getdata())
    w, h = img.size
    mostly_transparent = sum(1 for a in alpha_vals if a < 128) > len(alpha_vals) * 0.1

    rgb = img.convert("RGB").load()
    apx = alpha.load()
    min_x, min_y, max_x, max_y = w, h, 0, 0
    for y in range(h):
        for x in range(w):
            a = apx[x, y]
            r, g, b = rgb[x, y]
            if mostly_transparent:
                is_content = a >= 128
            else:
                is_content = a >= 30 and (r + g + b) // 3 >= 25
            if is_content:
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)
    return (min_x, min_y, max_x + 1, max_y + 1)

def blackout_gemini_logo(img):
    """Make the Gemini sparkle corner transparent so it doesn't skew the bbox."""
    w, h = img.size
    patch_size = int(min(w, h) * 0.1)
    from PIL import ImageDraw
    draw = ImageDraw.Draw(img)
    # Use fully transparent (alpha 0) so bbox detection ignores this region
    draw.rectangle([(w - patch_size, h - patch_size), (w, h)], fill=(0, 0, 0, 0))
    return img

def crop_to_square(image_path):
    """Load, crop to content bbox, pad to square."""
    img = Image.open(image_path).convert("RGBA")
    img = blackout_gemini_logo(img)
    bbox = get_content_bbox(img)
    cropped = img.crop(bbox)
    w, h = cropped.size

    # For images that are roughly square (like the done/gift image),
    # add horizontal padding to make them match the wider aspect ratio of other images.
    # Wide images: keep as-is, just pad to square.
    # Square-ish images: extend horizontally so the character appears smaller in frame.
    aspect = w / h if h > 0 else 1.0
    if aspect < 1.3:
        # Square-ish — extend width to match aspect ~2:1 like the wider sprites
        new_w = int(h * 2.0)
        side = new_w
    else:
        side = max(w, h)

    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.paste(cropped, ((side - w) // 2, (side - h) // 2))
    return square

def encode_sprite(image_path, grid):
    """Returns (palette, base64_pixel_data). Palette index 0 is always transparent."""
    img = crop_to_square(image_path)

    # Detect if image is mostly on black background (like original JPGs)
    alpha = img.split()[-1]
    alpha_vals = list(alpha.getdata())
    mostly_transparent = sum(1 for a in alpha_vals if a < 128) > len(alpha_vals) * 0.1

    # NEAREST keeps pixel art sharp, no interpolation bleed
    img = img.resize((grid, grid), Image.NEAREST)

    rgb = img.convert("RGB")
    alpha = img.split()[-1]

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

            # Transparent logic:
            # - If image has transparent regions, trust alpha only (strict)
            # - Otherwise (black bg), use brightness threshold
            if mostly_transparent:
                is_transparent = a < 128
            else:
                is_transparent = a < 30 or (r + g + b) // 3 < 25

            if is_transparent:
                indices.append(0)
            else:
                indices.append(qpixels[x, y] + 1)

    return palette, base64.b64encode(bytes(indices)).decode("ascii")

# Generate Swift
lines = []
lines.append("import SwiftUI")
lines.append("")
lines.append("/// High-resolution pixel art sprites (256x256). Palette + base64 encoded.")
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
# Animation helpers
lines.append("    private func scaleFor(time t: Double) -> CGFloat {")
lines.append("        switch state {")
lines.append("        case .idle: return 1.0 + 0.04 * sin(t * 2 * .pi / 4.0)")
lines.append("        case .done: return 1.0 + 0.05 * sin(t * 2 * .pi / 1.5)")
lines.append("        default: return 1.0")
lines.append("        }")
lines.append("    }")
lines.append("")
lines.append("    private func offsetFor(time t: Double) -> CGSize {")
lines.append("        switch state {")
lines.append("        case .working:")
lines.append("            let y = abs(sin(t * 2 * .pi / 0.5)) * 2")
lines.append("            return CGSize(width: 0, height: -y)")
lines.append("        case .needsApproval:")
lines.append("            let x = sin(t * 2 * .pi / 0.6) * 2")
lines.append("            return CGSize(width: x, height: 0)")
lines.append("        default: return .zero")
lines.append("        }")
lines.append("    }")
lines.append("")
lines.append("    private func rotationFor(time t: Double) -> Double {")
lines.append("        switch state {")
lines.append("        case .working: return sin(t * 2 * .pi / 0.5) * 1.5")
lines.append("        default: return 0")
lines.append("        }")
lines.append("    }")
lines.append("")
lines.append("    @ViewBuilder")
lines.append("    private func overlayFor(time t: Double) -> some View {")
lines.append("        if state == .done {")
lines.append("            Circle()")
lines.append("                .fill(Color.yellow.opacity(0.15 + 0.15 * sin(t * 2 * .pi / 1.5)))")
lines.append("                .blur(radius: 8)")
lines.append("        } else {")
lines.append("            EmptyView()")
lines.append("        }")
lines.append("    }")
lines.append("")

# Encode each state
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

    # Palette
    lines.append(f"    static let palette_{key}: [Pixel] = [")
    for r, g, b, _ in palette:
        lines.append(f"        (r: {r/255:.3f}, g: {g/255:.3f}, b: {b/255:.3f}),")
    lines.append("    ]")
    lines.append("")

    # Base64 data
    lines.append(f"    static let data_{key}: String = \"{b64}\"")
    lines.append("")

    print(f"✓ {name}: {len(palette)} colors, {len(b64)} chars of data")

lines.append("}")

with open(OUT, "w") as f:
    f.write("\n".join(lines))

print(f"\n✓ Generated: {OUT}")
