#!/bin/bash
# ClaudeTap Setup Script
# Run this once to configure everything.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$HOME/.config/claudetap"
TOPIC_FILE="$CONFIG_DIR/topic"

echo "🔧 ClaudeTap Setup"
echo "=================="
echo ""

# 1. Topic
if [ -f "$TOPIC_FILE" ]; then
    TOPIC=$(cat "$TOPIC_FILE")
    echo "✓ Topic already configured: $TOPIC"
else
    TOPIC="claudetap-$(openssl rand -hex 6)"
    mkdir -p "$CONFIG_DIR"
    echo "$TOPIC" > "$TOPIC_FILE"
    echo "✓ Generated topic: $TOPIC"
fi

echo ""

# 2. Test ntfy connection
echo "Testing ntfy.sh connection..."
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -d '{"status":"test"}' "https://ntfy.sh/$TOPIC" 2>/dev/null)
if [ "$RESPONSE" = "200" ]; then
    echo "✓ ntfy.sh is reachable"
else
    echo "✗ ntfy.sh returned HTTP $RESPONSE — check your network"
fi

echo ""

# 3. Check Xcode
if xcode-select -p &>/dev/null; then
    echo "✓ Xcode command line tools found"
else
    echo "✗ Xcode not found — install from the App Store"
fi

echo ""

# 4. Generate Xcode project
if command -v xcodegen &>/dev/null; then
    echo "Generating Xcode project..."
    cd "$SCRIPT_DIR"
    xcodegen generate 2>&1
    echo "✓ Xcode project generated"
else
    echo "✗ XcodeGen not found — install with: brew install xcodegen"
fi

echo ""
echo "=================="
echo "Next steps:"
echo "  1. Open ClaudeTap.xcodeproj in Xcode"
echo "  2. For each target, go to Signing & Capabilities → select your Personal Team"
echo "  3. Connect your iPhone + Apple Watch"
echo "  4. Build & Run (⌘R)"
echo "  5. In the iOS app, enter this topic: $TOPIC"
echo "  6. Add the ClaudeTap complication to your watch face"
echo ""
echo "Your topic (copy this into the app): $TOPIC"
