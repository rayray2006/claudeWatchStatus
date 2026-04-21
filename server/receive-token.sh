#!/bin/bash
# Listens on ntfy for the Watch's APNs device token and saves it locally.
# Run this in a terminal, then open the ClaudeTap app on your Watch.

TOPIC="claudetap-token-4d845a7d2113"
SERVER_DIR="$(cd "$(dirname "$0")" && pwd)"
TOKEN_FILE="$SERVER_DIR/device-token.txt"

echo "Listening for device token on ntfy.sh/$TOPIC..."
echo "Open ClaudeTap on your Watch to register."
echo ""

curl -s "https://ntfy.sh/$TOPIC/json" | while IFS= read -r line; do
    token=$(echo "$line" | grep -oE '"message":"[a-f0-9]+"' | sed 's/"message":"//;s/"//')
    if [ -n "$token" ] && [ ${#token} -ge 32 ]; then
        echo "$token" > "$TOKEN_FILE"
        echo "✓ Saved token: ${token:0:16}..."
        echo "Saved to: $TOKEN_FILE"
        exit 0
    fi
done
