#!/usr/bin/env bash
# Run all Bubblewrap sandbox tests
#
# This script runs each test and reports a summary at the end

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================"
echo "  Bubblewrap Sandbox Test Suite"
echo "========================================"
echo ""

# Check if bwrap is installed
if ! command -v bwrap &> /dev/null; then
  echo "ERROR: Bubblewrap (bwrap) is not installed"
  echo "Install it with: sudo apt install bubblewrap"
  exit 1
fi

echo "Bubblewrap version: $(bwrap --version)"
echo ""

TESTS=(
  "test1-home-hidden.sh"
  "test2-readonly.sh"
  "test3-write-pwd.sh"
  "test4-process-isolation.sh"
  "test5-tmp-isolation.sh"
  "test6-ssh-agent.sh"
)

PASSED=0
FAILED=0
SKIPPED=0

for test in "${TESTS[@]}"; do
  echo "----------------------------------------"
  if [ -x "$test" ]; then
    if "./$test"; then
      ((PASSED++))
    else
      EXIT_CODE=$?
      if [ $EXIT_CODE -eq 0 ]; then
        ((SKIPPED++))
      else
        ((FAILED++))
      fi
    fi
  else
    echo "WARNING: $test is not executable, skipping"
    ((SKIPPED++))
  fi
  echo ""
done

echo "========================================"
echo "  Test Summary"
echo "========================================"
echo "  Passed:  $PASSED"
echo "  Failed:  $FAILED"
echo "  Skipped: $SKIPPED"
echo "========================================"

if [ $FAILED -gt 0 ]; then
  exit 1
fi
exit 0
