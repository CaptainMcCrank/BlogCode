#!/usr/bin/env bash
# Test 5: Confirm /tmp isolation
#
# Expected: cat fails with "No such file or directory"
# The sandbox should have its own isolated /tmp

set -e

echo "=== Test 5: /tmp Isolation ==="
echo ""

# Create a test file in host /tmp
TEST_FILE="/tmp/bwrap-test-secret-$$"
echo "secret from host" > "$TEST_FILE"
echo "Created test file: $TEST_FILE"

# Try to read it from inside the sandbox
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
  /bin/cat "$TEST_FILE" 2>&1) || true

# Clean up
rm -f "$TEST_FILE"

echo "Output from sandbox:"
echo "$RESULT"
echo ""

if echo "$RESULT" | grep -q "No such file or directory"; then
  echo "PASS: /tmp is isolated - sandbox cannot see host's /tmp files"
  exit 0
else
  echo "FAIL: Sandbox may be able to see host's /tmp"
  exit 1
fi
