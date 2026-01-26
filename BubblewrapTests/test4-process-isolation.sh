#!/usr/bin/env bash
# Test 4: Confirm process isolation
#
# Expected: Shows only a few processes (bwrap and ps)
# The sandbox should hide other system processes

set -e

echo "=== Test 4: Process Isolation ==="
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
  --unshare-pid \
  --chdir "$PWD" \
  /bin/ps aux 2>&1)

echo "Processes visible inside sandbox:"
echo "$RESULT"
echo ""

# Count non-header lines (actual processes)
PROC_COUNT=$(echo "$RESULT" | tail -n +2 | wc -l)

echo "Process count: $PROC_COUNT"
echo ""

if [ "$PROC_COUNT" -le 3 ]; then
  echo "PASS: Process isolation is working (only $PROC_COUNT processes visible)"
  exit 0
else
  echo "FAIL: Too many processes visible ($PROC_COUNT), isolation may not be working"
  exit 1
fi
