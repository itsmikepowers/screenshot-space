#!/bin/bash
# Reads and outputs the handoff file contents so they're immediately
# available in context without consuming tokens on a file read.
HANDOFF_FILE="$(git rev-parse --show-toplevel)/.blueprint/handoff/handoff.md"
if [ ! -s "$HANDOFF_FILE" ]; then
  echo "NO_HANDOFF: The handoff file is empty or missing. There is no prior session to resume."
  exit 0
fi
echo "=== HANDOFF CONTEXT ==="
cat "$HANDOFF_FILE"
echo "=== END HANDOFF ==="
