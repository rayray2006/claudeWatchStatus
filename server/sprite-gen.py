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
from PIL import Image

ASSETS = "/Users/rayray/Documents/Code/ClaudeTap/ClaudeTapWatch/Assets.xcassets"
OUT = "/Users/rayray/Documents/Code/ClaudeTap/Shared/ClaudeSprites.swift"
GRID = 512

states = {
    "idle": "ClaudeIdle",
    "working": "ClaudeWorking",
    "done": "ClaudeDone",
    "approval": "ClaudeApproval",
}


def load_and_prepare(path: str, grid: int) -> bytes:
    """Open the source image, pad to square if needed, downsample to grid×grid,
    and return raw RGBA bytes (grid*grid*4)."""
    img = Image.open(path).convert("RGBA")

    w, h = img.size
    side = max(w, h)
    if (w, h) != (side, side):
        square = Image.new("RGBA", (side, side), (0, 0, 0, 255))
        square.paste(img, ((side - w) // 2, (side - h) // 2))
        img = square

    if img.size != (grid, grid):
        img = img.resize((grid, grid), Image.NEAREST)

    return img.tobytes()  # raw RGBA, row-major, top-left origin


lines: list[str] = [
    "import SwiftUI",
    "",
    f"/// Lossless pixel art sprites, embedded as raw {GRID}×{GRID} RGBA byte",
    "/// streams (base64 encoded) and rendered pixel-by-pixel via Canvas.",
    "/// No palette quantization, no PNG decode, no UIImage in the render path.",
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

    raw = load_and_prepare(source, GRID)
    b64 = base64.b64encode(raw).decode("ascii")

    lines.append(f"    private static let data_{key}: String = \"{b64}\"")
    lines.append("")

    print(f"  ✓ {asset_name}: {len(raw)} raw bytes → {len(b64)} base64 chars")

lines.append("}")

with open(OUT, "w") as f:
    f.write("\n".join(lines))

print(f"\n✓ Generated: {OUT} ({os.path.getsize(OUT)} bytes)")
