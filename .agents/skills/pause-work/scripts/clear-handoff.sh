#!/bin/bash
# Clears the handoff file so the skill always starts with a blank slate.
# This runs before the skill body, saving tokens on deletion.
HANDOFF_FILE="$(git rev-parse --show-toplevel)/.blueprint/handoff/handoff.md"
> "$HANDOFF_FILE"
echo "Handoff file cleared: $HANDOFF_FILE"
