#!/usr/bin/env bash
# Test 2: Confirm you cannot write to read-only paths
#
# Expected: Fails with "Read-only file system"
# The sandbox should prevent writes to paths mounted with --ro-bind

set -e

echo "=== Test 2: Read-Only Path Enforcement ==="
echo ""

# Check if .gitconfig exists
if [ ! -f "$HOME/.gitconfig" ]; then
  echo "SKIP: $HOME/.gitconfig does not exist on this system"
  echo "Create a .gitconfig file or modify this test to use a different file"
  exit 0
fi

RESULT=$(bwrap \
  --ro-bind /usr /usr \
  --ro-bind /lib /lib \
  --ro-bind /lib64 /lib64 \
  --ro-bind /bin /bin \
  --ro-bind "$HOME/.gitconfig" "$HOME/.gitconfig" \
  --bind "$PWD" "$PWD" \
  --tmpfs /tmp \
  --proc /proc \
  --dev /dev \
  --chdir "$PWD" \
  /bin/sh -c "echo 'test' >> $HOME/.gitconfig" 2>&1) || true

echo "Output from sandbox:"
echo "$RESULT"
echo ""

if echo "$RESULT" | grep -qi "read-only"; then
  echo "PASS: Write to read-only path was blocked"
  exit 0
else
  echo "FAIL: Write to read-only path may have succeeded"
  exit 1
fi
