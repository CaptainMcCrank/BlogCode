#!/usr/bin/env bash
# Test 1: Confirm your home directory contents are hidden
#
# Expected: Both ls commands fail with "No such file or directory"
# The sandbox should hide home directory contents like .bashrc and Documents

set -e

echo "=== Test 1: Home Directory Contents Hidden ==="
echo ""

RESULT=$(bwrap \
  --ro-bind /usr /usr \
  --ro-bind /lib /lib \
  --ro-bind /lib64 /lib64 \
  --ro-bind /bin /bin \
  --bind "$PWD" "$PWD" \
  --tmpfs /tmp \
  --proc /proc \
  --dev /dev \
  --chdir "$PWD" \
  /bin/sh -c "ls $HOME/.bashrc 2>&1; ls $HOME/Documents 2>&1" 2>&1) || true

echo "Output from sandbox:"
echo "$RESULT"
echo ""

if echo "$RESULT" | grep -q "No such file or directory"; then
  echo "PASS: Home directory contents are hidden"
  exit 0
else
  echo "FAIL: Home directory contents may be visible"
  exit 1
fi
