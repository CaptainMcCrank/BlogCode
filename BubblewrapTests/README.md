# Bubblewrap Sandbox Tests

This directory contains test scripts to verify that your Bubblewrap sandbox configuration is working correctly. These tests validate the security boundaries described in the accompanying blog post about sandboxing Claude Code.

## How These Tests Work

Each test follows the same pattern to verify that Bubblewrap's access controls function correctly:

1. **Create a restricted container**: We invoke `bwrap` with a specific configuration that intentionally limits what the sandboxed process can see and do. For example, we might bind-mount only `/usr`, `/lib`, `/bin`, and the current working directory—leaving the rest of the filesystem unmapped.

2. **Attempt a prohibited action**: From inside the container, we spawn a shell and attempt to access a resource we know should be blocked. For instance, we try to read `~/.bashrc` when the home directory was never mounted, or write to a file on a read-only mount.

3. **Verify the expected failure**: If Bubblewrap is working correctly, the prohibited action fails with a predictable error (e.g., "No such file or directory" or "Read-only file system"). The test script checks for this error message.

This approach—attempting to breach a known barrier and confirming the attempt fails—demonstrates that the sandbox boundaries are enforced. If a test passes, it means the container successfully prevented access to a protected resource. If a test fails, it indicates a gap in the sandbox configuration that needs investigation.

## Prerequisites

- **Bubblewrap** must be installed on your system
  ```bash
  # Debian/Ubuntu
  sudo apt install bubblewrap

  # Fedora
  sudo dnf install bubblewrap

  # Arch Linux
  sudo pacman -S bubblewrap
  ```

- **SSH agent** (for Test 6) - most desktop environments start one automatically. Check with:
  ```bash
  echo $SSH_AUTH_SOCK
  ```

## Running the Tests

### Run All Tests

```bash
cd BubblewrapTests
chmod +x *.sh
./run-all-tests.sh
```

### Run Individual Tests

Each test can be run independently:

```bash
./test1-home-hidden.sh      # Verify home directory contents are hidden
./test2-readonly.sh         # Verify read-only mounts cannot be written
./test3-write-pwd.sh        # Verify working directory is writable
./test4-process-isolation.sh # Verify process namespace isolation
./test5-tmp-isolation.sh    # Verify /tmp is isolated
./test6-ssh-agent.sh        # Verify SSH agent works but keys are hidden
```

## Test Descriptions

| Test | What It Verifies |
|------|------------------|
| **Test 1** | Home directory contents (like `.bashrc`, `Documents`) are not visible inside the sandbox |
| **Test 2** | Paths mounted with `--ro-bind` cannot be modified |
| **Test 3** | The current working directory (mounted with `--bind`) is writable |
| **Test 4** | Process isolation via `--unshare-pid` hides host processes |
| **Test 5** | The sandbox has its own isolated `/tmp` via `--tmpfs` |
| **Test 6** | SSH agent is accessible but private key files are not exposed |

## Expected Results

A passing test suite looks like:

```
========================================
  Test Summary
========================================
  Passed:  6
  Failed:  0
  Skipped: 0
========================================
```

Some tests may be skipped if prerequisites are missing (e.g., no SSH agent running, no `.gitconfig` file). Skipped tests are not failures.

## Troubleshooting

### Test 6 fails with "No SSH agent running"

Your desktop environment may not have started an SSH agent, or `SSH_AUTH_SOCK` is not set. Options:

1. Use GNOME keyring (check if `/run/user/$(id -u)/keyring/ssh` exists)
2. Start an agent manually with a custom socket location:
   ```bash
   ssh-agent -a /run/user/$(id -u)/ssh-agent.sock
   export SSH_AUTH_SOCK=/run/user/$(id -u)/ssh-agent.sock
   ssh-add ~/.ssh/your_key
   ```

**Note:** Manually started agents that use `/tmp` for their socket will not work with these tests because the sandbox isolates `/tmp`.

### Permission denied errors

Ensure the test scripts are executable:
```bash
chmod +x *.sh
```

### bwrap: command not found

Install Bubblewrap using your system's package manager (see Prerequisites above).

## Tested Environment

These scripts were tested on:

| Component | Version |
|-----------|---------|
| OS | Pop!_OS 22.04 LTS |
| Kernel | 6.16.3-76061603-generic |
| Architecture | x86_64 |
| Bubblewrap | 0.6.1 |
| SSH Agent | GNOME Keyring (`/run/user/1000/keyring/ssh`) |

The tests should work on other Linux distributions with Bubblewrap installed, though paths and behaviors may vary slightly.

## Review Support

These test scripts were reviewed with AI assistance to ensure accuracy and completeness.
