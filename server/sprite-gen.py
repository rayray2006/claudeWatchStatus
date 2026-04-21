#!/usr/bin/env python3
"""
Embed the source pixel-art PNGs directly into Swift as base64 strings.
The Swift runtime decodes the PNG bytes through UIImage — completely
lossless, no palette quantization, no resampling artifacts. Preserves full
source resolution.
"""
import base64
import os

ASSETS = "/Users/rayray/Documents/Code/ClaudeTap/ClaudeTapWatch/Assets.xcassets"
OUT = "/Users/rayray/Documents/Code/ClaudeTap/Shared/ClaudeSprites.swift"

states = {
    "idle": "ClaudeIdle",
    "working": "ClaudeWorking",
    "done": "ClaudeDone",
    "approval": "ClaudeApproval",
}


def encode_png(path: str) -> str:
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("ascii")


lines: list[str] = [
    "import SwiftUI",
    "#if canImport(UIKit)",
    "import UIKit",
    "#endif",
    "",
    "/// Renders the Claude sprite for a given state.",
    "///",
    "/// The source PNGs are embedded as base64 in this file and decoded through",
    "/// UIImage at runtime — lossless, full source resolution, no palette",
    "/// quantization or resample artifacts.",
    "struct ClaudeSpriteView: View {",
    "    let state: TapState",
    "",
    "    var body: some View {",
    "        #if canImport(UIKit)",
    "        if let ui = Self.image(for: state) {",
    "            Image(uiImage: ui)",
    "                .resizable()",
    "                .interpolation(.high)",
    "                .aspectRatio(contentMode: .fit)",
    "        } else {",
    "            Color.clear",
    "        }",
    "        #else",
    "        Color.clear",
    "        #endif",
    "    }",
    "",
    "    #if canImport(UIKit)",
    "    /// Cached decoded images. Decoded once per process, shared across views.",
    "    private static let cache: [TapState: UIImage] = {",
    "        var out: [TapState: UIImage] = [:]",
    "        for (state, b64) in pairs {",
    "            if let data = Data(base64Encoded: b64), let img = UIImage(data: data) {",
    "                out[state] = img",
    "            }",
    "        }",
    "        return out",
    "    }()",
    "",
    "    private static var pairs: [(TapState, String)] {",
    "        [",
]
for key in states:
    state_case = "needsApproval" if key == "approval" else key
    lines.append(f"            (.{state_case}, data_{key}),")
lines += [
    "        ]",
    "    }",
    "",
    "    private static func image(for state: TapState) -> UIImage? {",
    "        cache[state]",
    "    }",
    "    #endif",
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

    b64 = encode_png(source)
    lines.append(f"    private static let data_{key}: String = \"{b64}\"")
    lines.append("")
    print(f"  ✓ {asset_name}: {len(b64)} base64 chars (from {os.path.getsize(source)} PNG bytes)")

lines.append("}")

with open(OUT, "w") as f:
    f.write("\n".join(lines))

print(f"\n✓ Generated: {OUT} ({os.path.getsize(OUT)} bytes)")
