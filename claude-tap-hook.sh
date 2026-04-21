#!/bin/bash
# ClaudeTap Claude Code hook — sends state update to Apple Watch via APNs.
#
# Usage: ./claude-tap-hook.sh working|done|approval
# Or via env: CLAUDETAP_STATUS=done ./claude-tap-hook.sh

STATUS="${1:-${CLAUDETAP_STATUS:-working}}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Send via APNs (requires server/device-token.txt and AuthKey_*.p8)
node "$SCRIPT_DIR/server/send-push.js" "$STATUS" &>/dev/null &

exit 0
