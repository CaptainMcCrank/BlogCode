#!/usr/bin/env bash
# Test 6: Confirm SSH agent works but keys are hidden
#
# Expected: ssh-add -l succeeds, cat ~/.ssh/id_* fails
# The sandbox can use the SSH agent but cannot read private key files

set -e

echo "=== Test 6: SSH Agent Access (Keys Hidden) ==="
echo ""

# Check for SSH_AUTH_SOCK
if [ -z "$SSH_AUTH_SOCK" ]; then
  # Try GNOME keyring location
  if [ -S "/run/user/$(id -u)/keyring/ssh" ]; then
    export SSH_AUTH_SOCK="/run/user/$(id -u)/keyring/ssh"
    echo "Using GNOME keyring SSH socket: $SSH_AUTH_SOCK"
  else
    echo "SKIP: No SSH agent running (SSH_AUTH_SOCK not set)"
    echo "Start an SSH agent or use a desktop environment with built-in agent"
    exit 0
  fi
fi

# Check if agent has keys
if ! ssh-add -l >/dev/null 2>&1; then
  echo "SKIP: No keys loaded in SSH agent"
  echo "Run: ssh-add ~/.ssh/your_key"
  exit 0
fi

echo "SSH agent is running with keys loaded"
echo "SSH_AUTH_SOCK: $SSH_AUTH_SOCK"
echo ""

# Check if known_hosts exists
if [ ! -f "$HOME/.ssh/known_hosts" ]; then
  echo "SKIP: $HOME/.ssh/known_hosts does not exist"
  exit 0
fi

# Find a private key file to test
KEY_FILE=""
for f in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_rsa" "$HOME/.ssh/id_ecdsa"; do
  if [ -f "$f" ]; then
    KEY_FILE="$f"
    break
  fi
done

if [ -z "$KEY_FILE" ]; then
  echo "SKIP: No private key files found to test"
  exit 0
fi

echo "Testing with key file: $KEY_FILE"
echo ""

# Run the test
RESULT=$(bwrap \
  --ro-bind /usr /usr \
  --ro-bind /lib /lib \
  --ro-bind /lib64 /lib64 \
  --ro-bind /bin /bin \
  --ro-bind "$HOME/.ssh/known_hosts" "$HOME/.ssh/known_hosts" \
  --bind "$(dirname $SSH_AUTH_SOCK)" "$(dirname $SSH_AUTH_SOCK)" \
  --bind "$PWD" "$PWD" \
  --tmpfs /tmp \
  --proc /proc \
  --dev /dev \
  --setenv SSH_AUTH_SOCK "$SSH_AUTH_SOCK" \
  --chdir "$PWD" \
  /bin/sh -c "echo '--- ssh-add -l:'; ssh-add -l 2>&1; echo '--- cat $KEY_FILE:'; cat $KEY_FILE 2>&1" 2>&1) || true

echo "Output from sandbox:"
echo "$RESULT"
echo ""

# Check results
AGENT_WORKS=$(echo "$RESULT" | grep -c "SHA256\|RSA\|ED25519\|ECDSA" || true)
KEY_HIDDEN=$(echo "$RESULT" | grep -c "No such file or directory" || true)

if [ "$AGENT_WORKS" -gt 0 ] && [ "$KEY_HIDDEN" -gt 0 ]; then
  echo "PASS: SSH agent works and private key is hidden"
  exit 0
elif [ "$AGENT_WORKS" -eq 0 ]; then
  echo "FAIL: SSH agent is not accessible from sandbox"
  exit 1
else
  echo "FAIL: Private key may be visible to sandbox"
  exit 1
fi
