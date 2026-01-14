#!/bin/bash
#
# Sandbox Escape Test Script
# Tests the security boundaries of a bubblewrap sandbox configuration
#
# Usage: Run this script INSIDE the sandbox to test what escapes are possible
#        ./sandbox-escape-test.sh
#
# Exit codes: 0 = all tests passed (sandbox is secure), non-zero = vulnerabilities found

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

VULNERABILITIES=0
WARNINGS=0

pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((VULNERABILITIES++))
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARNINGS++))
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

section() {
    echo ""
    echo "=============================================="
    echo " $1"
    echo "=============================================="
}

# Detect environment
PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
REAL_HOME="${HOME:-/home/unknown}"

section "1. FILESYSTEM ACCESS TESTS"

echo ""
echo "--- Testing access to sensitive directories ---"

# Test access to common sensitive locations
SENSITIVE_PATHS=(
    "$REAL_HOME/.ssh"
    "$REAL_HOME/.aws"
    "$REAL_HOME/.gnupg"
    "$REAL_HOME/.config"
    "$REAL_HOME/.local"
    "$REAL_HOME/.bash_history"
    "$REAL_HOME/.zsh_history"
    "$REAL_HOME/.bashrc"
    "$REAL_HOME/.profile"
    "$REAL_HOME/Documents"
    "$REAL_HOME/Downloads"
    "$REAL_HOME/.password-store"
    "$REAL_HOME/.netrc"
    "$REAL_HOME/.docker"
    "$REAL_HOME/.kube"
    "/root"
    "/etc/shadow"
    "/etc/sudoers"
    "/var/log"
)

for path in "${SENSITIVE_PATHS[@]}"; do
    if [[ -r "$path" ]]; then
        fail "Can READ sensitive path: $path"
    else
        pass "Cannot read: $path"
    fi
done

echo ""
echo "--- Testing write access outside project ---"

# Try to write outside the allowed directory
WRITE_TEST_PATHS=(
    "/tmp/sandbox_write_test_$$"
    "$REAL_HOME/.ssh/sandbox_test_$$"
    "$REAL_HOME/sandbox_test_$$"
    "/etc/sandbox_test_$$"
    "/usr/sandbox_test_$$"
    "/var/sandbox_test_$$"
)

for path in "${WRITE_TEST_PATHS[@]}"; do
    if touch "$path" 2>/dev/null; then
        fail "Can WRITE to: $path"
        rm -f "$path" 2>/dev/null
    else
        pass "Cannot write to: $path"
    fi
done

# /tmp is tmpfs - writing here is expected, but check if it persists
if touch /tmp/test_$$ 2>/dev/null; then
    info "/tmp is writable (expected for tmpfs)"
    rm -f /tmp/test_$$
fi

echo ""
echo "--- Testing symlink escape attempts ---"

# Try to create symlinks that escape the sandbox
cd "$PROJECT_DIR" 2>/dev/null || cd /tmp

if ln -s /etc/passwd symlink_escape_test_$$ 2>/dev/null; then
    if [[ -r symlink_escape_test_$$ ]]; then
        # This is expected since /etc/passwd is ro-bound
        info "Symlink to /etc/passwd readable (but /etc/passwd is explicitly bound)"
    fi
    rm -f symlink_escape_test_$$
fi

if ln -s "$REAL_HOME/.ssh/id_rsa" symlink_ssh_test_$$ 2>/dev/null; then
    if [[ -r symlink_ssh_test_$$ ]]; then
        fail "Can read ~/.ssh/id_rsa via symlink!"
    else
        pass "Symlink to ~/.ssh/id_rsa not readable"
    fi
    rm -f symlink_ssh_test_$$
else
    pass "Cannot create symlink to ~/.ssh"
fi

section "2. PROCESS ISOLATION TESTS"

echo ""
echo "--- Testing PID namespace isolation ---"

# Count visible processes
PROC_COUNT=$(ls /proc | grep -E '^[0-9]+$' | wc -l)
info "Visible processes in /proc: $PROC_COUNT"

if [[ $PROC_COUNT -gt 50 ]]; then
    warn "Many processes visible ($PROC_COUNT) - PID namespace may not be isolated"
else
    pass "Limited process visibility ($PROC_COUNT processes)"
fi

# Try to see host PID 1
if [[ -r /proc/1/cmdline ]]; then
    INIT_CMD=$(cat /proc/1/cmdline 2>/dev/null | tr '\0' ' ')
    if [[ "$INIT_CMD" == *"systemd"* ]] || [[ "$INIT_CMD" == *"init"* ]]; then
        fail "Can see host init process: $INIT_CMD"
    else
        info "PID 1 is: $INIT_CMD"
    fi
fi

# Try to ptrace another process (should fail in good sandbox)
echo ""
echo "--- Testing ptrace restrictions ---"

if command -v strace &>/dev/null; then
    if strace -p 1 2>&1 | grep -q "Operation not permitted\|No such process"; then
        pass "Cannot ptrace PID 1"
    else
        warn "ptrace may be available"
    fi
else
    info "strace not available for testing"
fi

section "3. NETWORK ACCESS TESTS"

echo ""
echo "--- Testing network connectivity ---"

# Your config uses --share-net, so network should be available
if command -v curl &>/dev/null; then
    # Test general internet access
    if curl -s --connect-timeout 3 -o /dev/null https://google.com 2>/dev/null; then
        warn "Can reach google.com (unrestricted internet access)"
    else
        pass "Cannot reach google.com"
    fi
    
    # Test access to cloud metadata services (AWS, GCP, Azure)
    METADATA_URLS=(
        "http://169.254.169.254/latest/meta-data/"           # AWS
        "http://metadata.google.internal/computeMetadata/v1/" # GCP
        "http://169.254.169.254/metadata/instance"           # Azure
    )
    
    for url in "${METADATA_URLS[@]}"; do
        if curl -s --connect-timeout 2 -o /dev/null "$url" 2>/dev/null; then
            fail "Can reach cloud metadata service: $url"
        else
            pass "Cannot reach metadata: $url"
        fi
    done
    
    # Test localhost access
    if curl -s --connect-timeout 2 -o /dev/null http://127.0.0.1:22 2>/dev/null; then
        warn "Can reach localhost:22 (SSH)"
    fi
    
elif command -v wget &>/dev/null; then
    if wget -q --timeout=3 -O /dev/null https://google.com 2>/dev/null; then
        warn "Can reach google.com via wget (unrestricted internet access)"
    fi
else
    info "No curl or wget available for network testing"
fi

# Test DNS resolution
if command -v nslookup &>/dev/null; then
    if nslookup google.com &>/dev/null; then
        info "DNS resolution is working"
    fi
elif command -v host &>/dev/null; then
    if host google.com &>/dev/null; then
        info "DNS resolution is working"
    fi
fi

# Test raw socket capability
echo ""
echo "--- Testing raw socket access ---"

if command -v ping &>/dev/null; then
    if ping -c 1 -W 1 127.0.0.1 &>/dev/null; then
        info "ping works (raw sockets or ping_group_range configured)"
    else
        pass "ping failed (raw sockets restricted)"
    fi
fi

section "4. CAPABILITY AND PRIVILEGE TESTS"

echo ""
echo "--- Testing available capabilities ---"

if command -v capsh &>/dev/null; then
    CAPS=$(capsh --print 2>/dev/null | grep "Current:" | head -1)
    info "Capabilities: $CAPS"
    
    if [[ "$CAPS" == *"cap_sys_admin"* ]]; then
        fail "CAP_SYS_ADMIN is available!"
    fi
    if [[ "$CAPS" == *"cap_net_admin"* ]]; then
        warn "CAP_NET_ADMIN is available"
    fi
    if [[ "$CAPS" == *"cap_sys_ptrace"* ]]; then
        warn "CAP_SYS_PTRACE is available"
    fi
elif [[ -r /proc/self/status ]]; then
    CAP_EFF=$(grep CapEff /proc/self/status | awk '{print $2}')
    info "Effective capabilities (hex): $CAP_EFF"
    if [[ "$CAP_EFF" != "0000000000000000" ]]; then
        warn "Some capabilities are set: $CAP_EFF"
    else
        pass "No effective capabilities"
    fi
fi

echo ""
echo "--- Testing privilege escalation vectors ---"

# Check for setuid binaries in accessible paths
info "Checking for setuid binaries..."
SETUID_COUNT=$(find /usr /bin 2>/dev/null | xargs ls -la 2>/dev/null | grep -c "^-..s" || echo "0")
if [[ $SETUID_COUNT -gt 0 ]]; then
    warn "Found $SETUID_COUNT setuid binaries in /usr or /bin"
    # List them
    find /usr /bin -perm -4000 2>/dev/null | head -5 | while read -r f; do
        info "  setuid: $f"
    done
fi

# Test sudo
if command -v sudo &>/dev/null; then
    if sudo -n true 2>/dev/null; then
        fail "sudo works without password!"
    else
        pass "sudo requires authentication (or not available)"
    fi
fi

# Test su
if command -v su &>/dev/null; then
    if su -c "echo test" root 2>/dev/null; then
        fail "su to root works!"
    else
        pass "su to root blocked"
    fi
fi

section "5. MOUNT AND FILESYSTEM NAMESPACE TESTS"

echo ""
echo "--- Testing mount capabilities ---"

# Try to mount something
if mount -t tmpfs none /tmp/mount_test_$$ 2>/dev/null; then
    fail "Can mount filesystems!"
    umount /tmp/mount_test_$$ 2>/dev/null
    rmdir /tmp/mount_test_$$ 2>/dev/null
else
    pass "Cannot mount filesystems"
fi

# Check what's mounted
echo ""
echo "--- Examining mount points ---"

info "Current mounts:"
if [[ -r /proc/self/mounts ]]; then
    cat /proc/self/mounts | while read -r line; do
        mount_point=$(echo "$line" | awk '{print $2}')
        mount_opts=$(echo "$line" | awk '{print $4}')
        
        # Check for dangerous mount options
        if [[ "$mount_opts" == *"rw"* ]] && [[ "$mount_point" != "/tmp"* ]] && [[ "$mount_point" != "$PROJECT_DIR"* ]] && [[ "$mount_point" != *".claude"* ]]; then
            warn "  RW mount outside expected dirs: $mount_point"
        fi
    done
fi

# Try to remount read-only filesystems as read-write
if mount -o remount,rw /usr 2>/dev/null; then
    fail "Can remount /usr as read-write!"
else
    pass "Cannot remount /usr"
fi

section "6. INFORMATION DISCLOSURE TESTS"

echo ""
echo "--- Testing access to sensitive system information ---"

# Environment variables that might leak secrets
SENSITIVE_VARS=(
    "AWS_ACCESS_KEY_ID"
    "AWS_SECRET_ACCESS_KEY"
    "GITHUB_TOKEN"
    "GH_TOKEN"
    "ANTHROPIC_API_KEY"
    "OPENAI_API_KEY"
    "DATABASE_URL"
    "DB_PASSWORD"
    "SECRET_KEY"
    "PRIVATE_KEY"
)

for var in "${SENSITIVE_VARS[@]}"; do
    if [[ -n "${!var:-}" ]]; then
        fail "Sensitive env var is set: $var"
    fi
done
pass "No common sensitive env vars found"

# Check if we can read other users' info
if [[ -r /etc/passwd ]]; then
    USER_COUNT=$(wc -l < /etc/passwd)
    info "/etc/passwd is readable ($USER_COUNT users) - this is expected"
fi

# Check /proc for information leaks
if [[ -r /proc/self/environ ]]; then
    info "/proc/self/environ is readable (own environment)"
fi

# Try to read kernel memory (should fail)
if [[ -r /dev/mem ]]; then
    fail "/dev/mem is readable!"
else
    pass "/dev/mem not accessible"
fi

if [[ -r /dev/kmem ]]; then
    fail "/dev/kmem is readable!"
else
    pass "/dev/kmem not accessible"
fi

section "7. CONTAINER/SANDBOX ESCAPE VECTORS"

echo ""
echo "--- Testing common escape techniques ---"

# Check for Docker socket
if [[ -e /var/run/docker.sock ]]; then
    fail "Docker socket is accessible!"
else
    pass "Docker socket not accessible"
fi

# Check for containerd socket  
if [[ -e /run/containerd/containerd.sock ]]; then
    fail "Containerd socket is accessible!"
else
    pass "Containerd socket not accessible"
fi

# Check cgroup escape potential
if [[ -w /sys/fs/cgroup ]]; then
    warn "/sys/fs/cgroup is writable - potential escape vector"
else
    pass "/sys/fs/cgroup not writable"
fi

# Check for kernel module loading
if [[ -w /proc/sys/kernel/modprobe ]]; then
    fail "Can write to /proc/sys/kernel/modprobe!"
else
    pass "Cannot modify kernel module loading"
fi

# Try to access host filesystem through /proc
if [[ -r /proc/1/root ]] && [[ -d /proc/1/root/etc ]]; then
    warn "/proc/1/root is accessible - may indicate weak isolation"
else
    pass "/proc/1/root not accessible or PID 1 is sandboxed"
fi

section "8. SPECIFIC CONFIGURATION WEAKNESSES"

echo ""
echo "--- Analyzing your specific bwrap configuration ---"

# Your config binds .gitconfig - check what's in it
if [[ -r "$REAL_HOME/.gitconfig" ]]; then
    info ".gitconfig is readable (explicitly bound)"
    if grep -qi "token\|password\|credential" "$REAL_HOME/.gitconfig" 2>/dev/null; then
        warn ".gitconfig may contain credentials"
    fi
fi

# Your config binds .nvm - check if it's exploitable
if [[ -d "$REAL_HOME/.nvm" ]]; then
    info ".nvm directory is accessible"
    if [[ -w "$REAL_HOME/.nvm" ]]; then
        fail ".nvm is WRITABLE - could inject malicious npm packages"
    else
        pass ".nvm is read-only"
    fi
fi

# Your config binds .claude with write access
if [[ -d "$REAL_HOME/.claude" ]]; then
    if [[ -w "$REAL_HOME/.claude" ]]; then
        info ".claude directory is writable (expected for Claude config)"
        # Check if there are sensitive files
        if [[ -r "$REAL_HOME/.claude/credentials" ]] || [[ -r "$REAL_HOME/.claude/config.json" ]]; then
            info "  Claude credentials/config accessible (expected)"
        fi
    fi
fi

# Check --share-net implications
echo ""
echo "--- Network sharing analysis ---"
info "Your config uses --share-net (full network access)"
warn "This allows:"
warn "  - Exfiltration of data to any external server"
warn "  - Access to local network services"
warn "  - Potential SSRF attacks"
warn "  - Access to cloud metadata services (if on cloud VM)"

# Check --unshare-pid effectiveness
if [[ -d /proc/1/ns ]]; then
    OUR_PIDNS=$(readlink /proc/self/ns/pid 2>/dev/null)
    info "Our PID namespace: $OUR_PIDNS"
fi

section "9. DATA EXFILTRATION TESTS"

echo ""
echo "--- Testing data exfiltration potential ---"

# With --share-net, we can exfiltrate data
# This is a demonstration, not actual exfiltration

# Check if we can reach external DNS
if command -v dig &>/dev/null; then
    if dig +short google.com &>/dev/null; then
        warn "DNS exfiltration possible (can encode data in DNS queries)"
    fi
fi

# Check if we can make HTTPS connections
if command -v curl &>/dev/null; then
    if curl -s --connect-timeout 2 https://httpbin.org/ip &>/dev/null; then
        warn "HTTPS exfiltration possible (can send data to any HTTPS endpoint)"
    fi
fi

# Check if git can reach external repos
if command -v git &>/dev/null; then
    if git ls-remote https://github.com/octocat/Hello-World.git HEAD &>/dev/null 2>&1; then
        warn "Git exfiltration possible (can push to arbitrary remotes)"
    fi
fi

section "10. SUMMARY"

echo ""
echo "=============================================="
echo " TEST RESULTS"
echo "=============================================="
echo ""

if [[ $VULNERABILITIES -eq 0 ]] && [[ $WARNINGS -eq 0 ]]; then
    echo -e "${GREEN}All tests passed! Sandbox appears secure.${NC}"
elif [[ $VULNERABILITIES -eq 0 ]]; then
    echo -e "${YELLOW}No critical vulnerabilities, but $WARNINGS warnings found.${NC}"
else
    echo -e "${RED}Found $VULNERABILITIES potential vulnerabilities and $WARNINGS warnings.${NC}"
fi

echo ""
echo "Vulnerabilities: $VULNERABILITIES"
echo "Warnings: $WARNINGS"
echo ""

echo "--- KEY RECOMMENDATIONS FOR YOUR CONFIG ---"
echo ""
echo "1. CRITICAL: Replace --share-net with --unshare-net + proxy filtering"
echo "   Your current config allows unrestricted network access."
echo ""
echo "2. Consider making .nvm read-only (--ro-bind instead of implicit access)"
echo ""  
echo "3. Add --new-session to prevent TTY hijacking (CVE-2017-5226)"
echo ""
echo "4. Consider adding seccomp filters to restrict syscalls"
echo ""
echo "5. Add --unshare-user for user namespace isolation"
echo ""
echo "6. Explicitly deny /sys and /run access (not currently blocked)"
echo ""

exit $VULNERABILITIES

Next, let’s invoke bwrap and run the test script!

PROJECT_DIR="$HOME/Development/YourProject"
bwrap \
     --ro-bind /usr /usr \
     --ro-bind /lib /lib \
     --ro-bind /lib64 /lib64 \
     --ro-bind /bin /bin \
     --ro-bind /etc/resolv.conf /etc/resolv.conf \
     --ro-bind /etc/hosts /etc/hosts \
     --ro-bind /etc/ssl /etc/ssl \
     --ro-bind /etc/passwd /etc/passwd \
     --ro-bind /etc/group /etc/group \
     --ro-bind "$HOME/.gitconfig" "$HOME/.gitconfig" \
     --ro-bind "$HOME/.nvm" "$HOME/.nvm" \
     --bind "$PROJECT_DIR" "$PROJECT_DIR" \
     --bind "$HOME/.claude" "$HOME/.claude" \
     --tmpfs /tmp \
     --proc /proc \
     --dev /dev \
     --share-net \
     --unshare-pid \
     --die-with-parent \
     --chdir "$PROJECT_DIR" \
     bash ./sandbox-escape-test.sh
