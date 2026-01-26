#!/usr/bin/env bash
# Test 3: Confirm you CAN write to the working directory
#
# Expected: Prints "Write access confirmed"
# The sandbox should allow writes to paths mounted with --bind

set -e

echo "=== Test 3: Write Access to Working Directory ==="
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
  /bin/sh -c "touch sandbox-test-file && rm sandbox-test-file && echo 'Write access confirmed'" 2>&1)

echo "Output from sandbox:"
echo "$RESULT"
echo ""

if echo "$RESULT" | grep -q "Write access confirmed"; then
  echo "PASS: Write access to working directory works"
  exit 0
else
  echo "FAIL: Could not write to working directory"
  exit 1
fi
