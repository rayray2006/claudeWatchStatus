#!/usr/bin/env python3
"""
Convert the source images into raw RGBA byte streams, base64-encoded and
embedded into Swift. The Watch renders them pixel-by-pixel via Canvas —
no palette quantization, no PNG/UIImage decode at render time. Lossless
at the chosen grid resolution.

Preserves the source image as-is. No background processing, no threshold.
The app is rendered on a black background so black source backgrounds
simply blend in.
"""
import base64
import os
from collections import deque
from PIL import Image

ASSETS = "/Users/rayray/Documents/Code/ClaudeTap/ClaudeTapWatch/Assets.xcassets"
OUT = "/Users/rayray/Documents/Code/ClaudeTap/Shared/ClaudeSprites.swift"
GRID = 512
# Max RGB value a pixel can have and still be flood-filled as background.
BG_THRESHOLD = 25


def flood_fill_bg(img: Image.Image) -> Image.Image:
    """Flood-fill from the image edges, making dark pixels connected to the
    border transparent. Interior dark pixels (hammer, pencil, clock face)
    are preserved because they're surrounded by bright character pixels.
    Without this, the watch complication must render every pixel including
    the entire black background and blows through its render budget."""
    w, h = img.size
    px = img.load()

    def is_bg(x: int, y: int) -> bool:
        r, g, b, _ = px[x, y]
        return max(r, g, b) <= BG_THRESHOLD

    visited = bytearray(w * h)
    queue: deque[tuple[int, int]] = deque()

    def seed(x: int, y: int) -> None:
        if not visited[y * w + x] and is_bg(x, y):
            visited[y * w + x] = 1
            queue.append((x, y))

    for x in range(w):
        seed(x, 0)
        seed(x, h - 1)
    for y in range(h):
        seed(0, y)
        seed(w - 1, y)

    while queue:
        x, y = queue.popleft()
        px[x, y] = (0, 0, 0, 0)
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not visited[ny * w + nx] and is_bg(nx, ny):
                visited[ny * w + nx] = 1
                queue.append((nx, ny))

    return img


states = {
    "idle": "ClaudeIdle",
    "working": "ClaudeWorking",
    "done": "ClaudeDone",
    "approval": "ClaudeApproval",
}

# Per-state content-bbox margin. None = skip the crop entirely (preserve the
# source framing exactly). A small number = tight crop → character fills more
# of the frame. A larger number = looser crop → character appears smaller.
crop_margins: dict[str, float | None] = {
    "idle": 0.06,
    "working": 0.06,
    "done": 0.12,
    "approval": 0.03,
}


def content_bbox(img: Image.Image) -> tuple[int, int, int, int] | None:
    """Tight bounding box of non-transparent content, or None if all transparent."""
    alpha = img.split()[-1]
    bbox = alpha.getbbox()  # returns (l, t, r, b) of non-zero alpha region
    return bbox


def load_and_prepare(path: str, grid: int, crop_margin: float | None) -> bytes:
    """Open the source image, make the edge-connected black background
    transparent, optionally crop tight to the character (with `crop_margin` as
    a fraction of the content size), pad to square, downsample to grid×grid,
    return raw RGBA bytes (grid*grid*4)."""
    img = Image.open(path).convert("RGBA")
    img = flood_fill_bg(img)

    # Crop tight to content so the character fills the frame. None = skip crop.
    if crop_margin is not None and (bbox := content_bbox(img)) is not None:
        l, t, r, b = bbox
        content_w = r - l
        content_h = b - t
        margin = int(max(content_w, content_h) * crop_margin)
        l = max(0, l - margin)
        t = max(0, t - margin)
        r = min(img.width, r + margin)
        b = min(img.height, b + margin)
        img = img.crop((l, t, r, b))

    w, h = img.size
    side = max(w, h)
    if (w, h) != (side, side):
        square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        square.paste(img, ((side - w) // 2, (side - h) // 2), img)
        img = square

    if img.size != (grid, grid):
        img = img.resize((grid, grid), Image.NEAREST)

    return img.tobytes()


lines: list[str] = [
    "import SwiftUI",
    "",
    f"/// Lossless pixel art sprites, embedded as raw {GRID}×{GRID} RGBA byte",
    "/// streams (base64 encoded) and rendered pixel-by-pixel via Canvas.",
    "/// Canvas is used rather than Image-based paths because the WidgetKit",
    "/// widget extension doesn't reliably render Image-based sprites the way",
    "/// the main app does.",
    "struct ClaudeSpriteView: View {",
    "    let state: TapState",
    f"    static let grid: Int = {GRID}",
    "",
    "    var body: some View {",
    "        Canvas { ctx, size in",
    "            guard let bytes = Self.cache[state] else { return }",
    "            let grid = Self.grid",
    "            let cellW = size.width / CGFloat(grid)",
    "            let cellH = size.height / CGFloat(grid)",
    "            for y in 0..<grid {",
    "                for x in 0..<grid {",
    "                    let i = (y * grid + x) * 4",
    "                    let a = bytes[i + 3]",
    "                    if a < 4 { continue }",
    "                    let r = Double(bytes[i])     / 255.0",
    "                    let g = Double(bytes[i + 1]) / 255.0",
    "                    let b = Double(bytes[i + 2]) / 255.0",
    "                    let o = Double(a)            / 255.0",
    "                    let rect = CGRect(",
    "                        x: CGFloat(x) * cellW,",
    "                        y: CGFloat(y) * cellH,",
    "                        width: cellW + 0.5,",
    "                        height: cellH + 0.5",
    "                    )",
    "                    ctx.fill(Path(rect),",
    "                             with: .color(Color(red: r, green: g, blue: b, opacity: o)))",
    "                }",
    "            }",
    "        }",
    "    }",
    "",
    "    /// Decoded once per process. Indexed by state.",
    "    private static let cache: [TapState: [UInt8]] = {",
    "        var c: [TapState: [UInt8]] = [:]",
    "        for (state, b64) in sources {",
    "            if let data = Data(base64Encoded: b64) {",
    "                c[state] = Array(data)",
    "            }",
    "        }",
    "        return c",
    "    }()",
    "",
    "    private static var sources: [(TapState, String)] {",
    "        [",
]
for key in states:
    case_name = "needsApproval" if key == "approval" else key
    lines.append(f"            (.{case_name}, data_{key}),")
lines += [
    "        ]",
    "    }",
    "",
]

print("Encoding sprites...")
for key, asset_name in states.items():
    imageset = os.path.join(ASSETS, f"{asset_name}.imageset")
    source = None
    for f in os.listdir(imageset):
        if f.endswith(".png") or f.endswith(".jpg"):
            source = os.path.join(imageset, f)
            break
    if not source:
        print(f"  ⚠ No image for {asset_name}, skipping")
        continue

    raw = load_and_prepare(source, GRID, crop_margins.get(key))
    b64 = base64.b64encode(raw).decode("ascii")

    lines.append(f"    private static let data_{key}: String = \"{b64}\"")
    lines.append("")

    print(f"  ✓ {asset_name}: {len(raw)} raw bytes → {len(b64)} base64 chars")

lines.append("}")

with open(OUT, "w") as f:
    f.write("\n".join(lines))

print(f"\n✓ Generated: {OUT} ({os.path.getsize(OUT)} bytes)")
