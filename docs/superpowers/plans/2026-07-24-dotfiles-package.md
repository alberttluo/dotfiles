# Portable Dotfiles Package Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a dotfiles repo whose `install.sh` reproduces this machine's tmux, zsh, Neovim, Claude Code, and font setup on a fresh macOS or Red Hat Linux host.

**Architecture:** A three-layer config model — portable files symlinked from the repo, a gitignored `~/.zshrc.local` for machine-specific config, and machine state that is never touched. `install.sh` sources small step scripts (`install/NN-name.sh`), each defining one function with a tri-state return: 0 = ok, 1 = hard fail, 2 = warn-and-continue. Homebrew supplies every runtime dependency on both operating systems, so OS branching is confined to three points.

**Tech Stack:** POSIX-ish bash for the installer, zsh for the shipped config, bats-core for tests, shellcheck for static analysis, Docker (`rockylinux:9`) for the Linux integration test.

## Global Constraints

- Repo root is `/home/alluo/dotfiles`, branch `main`. **Never `git push`** — no remote is configured and the user explicitly forbade pushing.
- Every script starts `set -euo pipefail` and passes `shellcheck` with no warnings.
- Installer scripts are `#!/usr/bin/env bash`. Shipped shell config is zsh.
- OS detection resolves to exactly `macos` or `linux` — never `rhel`.
- Homebrew prefix is resolved at runtime by probing, in order: `/opt/homebrew/bin/brew`, `/usr/local/bin/brew`, `/home/linuxbrew/.linuxbrew/bin/brew`. Never hardcode a prefix.
- oh-my-tmux is pinned to commit `af33f07`.
- Nerd Fonts release is pinned to `v3.4.0`; asset `JetBrainsMono.zip` (verified present at that tag).
- Font destination: `~/Library/Fonts` on macos, `~/.local/share/fonts` on linux. `fc-cache -f` runs on linux only.
- tmux plugin path is `~/.config/tmux/plugins` (XDG). Never `~/.tmux/plugins`.
- Anything displaced is moved to `$BACKUP_DIR` = `~/.dotfiles-backup/<ISO-8601 timestamp>/`. Never delete, never overwrite in place.
- Every step is idempotent: re-running a completed step changes nothing and exits 0.
- **Never package or link:** `~/.claude/.credentials.json`, `history.jsonl`, `projects/`, `session-env/`, `sessions/`, `file-history/`, `paste-cache/`, `shell-snapshots/`, `hud/cache/`, `~/.claude.json`, `~/.zsh_history`. Use explicit allowlists, never a glob over `~/.claude`.
- Claude Code authentication is not automatable. The installer's closing summary tells the user to run `claude` and log in.

**Source of truth:** `docs/superpowers/specs/2026-07-24-tmux-zsh-packaging-design.md`.

## File Structure

| Path | Responsibility |
|---|---|
| `install.sh` | Flag parsing, step ordering and dispatch, summary. No install logic of its own. |
| `verify.sh` | Post-install assertions. Runnable standalone. |
| `lib/log.sh` | `log_step`/`log_ok`/`log_warn`/`log_fail`/`log_dry`, `run()` dry-run wrapper. |
| `lib/os.sh` | `detect_os`, `detect_arch`, `brew_prefix`, `ensure_homebrew`. |
| `lib/link.sh` | `backup_and_link`, `backup_and_copy`. The only code that writes to `$HOME`. |
| `install/00-preflight.sh` | `step_preflight` — OS/arch, required commands, Homebrew bootstrap, backup dir. |
| `install/10-packages.sh` | `step_packages` — `brew bundle`. |
| `install/20-fonts.sh` | `step_fonts` — download, extract, cache refresh. |
| `install/30-zsh.sh` | `step_zsh` — oh-my-zsh, link zsh config, seed `.zshrc.local`, `chsh`. |
| `install/40-tmux.sh` | `step_tmux` — oh-my-tmux clone, symlinks, tpm, plugins. |
| `install/50-nvim.sh` | `step_nvim` — link config, `Lazy! restore`. |
| `install/60-claude.sh` | `step_claude` — Claude Code install, link settings/CLAUDE.md/hud, render omc template. |
| `install/70-skills.sh` | `step_skills` — copy `~/.agents/skills`, recreate the 59-link farm. |
| `Brewfile` | Runtime deps: zsh, tmux, git, neovim, node. |
| `Brewfile.dev` | Dev-only: bats-core, shellcheck, shfmt. Never installed by `install.sh`. |
| `home/.zshrc` | Portable zsh config. Sources `.zshrc.local` last. |
| `home/.zshenv` | Guarded cargo env. |
| `home/.zshrc.local.example` | Template of this machine's EDA/WSL/corporate config, all commented. |
| `config/tmux/tmux.conf.local` | Verbatim copy from the source machine. |
| `config/nvim/` | Verbatim copy including `lazy-lock.json`. |
| `claude/settings.json` | Copy with agent-indicator hook paths moved to XDG. |
| `claude/CLAUDE.md` | Verbatim copy. |
| `claude/.omc-config.json.template` | `nodeBinary` as `@@NODE_BINARY@@`. |
| `claude/settings.local.json.example` | Permission allowlist + skip-perms opt-in, as a template. |
| `claude/hud/` | 5 vendored files, no `cache/`. |
| `agents/skills/` | All 61 skill directories (820K). |
| `agents/.skill-lock.json` | Provenance for all 61. |
| `agents/CLAUDE-SKILL-LINKS.txt` | The 59 names to link into `~/.claude/skills`. |
| `test/helper.bash` | Shared bats setup: sandboxed `$HOME`, command stubbing. |
| `test/*.bats` | One file per lib/step under test. |
| `test/Dockerfile.rocky9` | RHEL-family integration test image. |
| `README.md` | What this is, how to install, how to test, what is per-host. |
| `.gitignore` | `.omc/`, `.zshrc.local`, `settings.local.json`, machine state. |

---

### Task 1: Repo scaffolding, dev tooling, and logging

**Files:**
- Create: `.gitignore`, `Brewfile.dev`, `lib/log.sh`, `test/helper.bash`
- Test: `test/log.bats`

**Interfaces:**
- Consumes: nothing.
- Produces: `log_step MSG`, `log_ok MSG`, `log_warn MSG`, `log_fail MSG`, `log_dry MSG` (all write to stderr, return 0); `run CMD...` (executes `CMD` unless `DRY_RUN=1`, in which case it calls `log_dry` with the command and returns 0); globals `WARNINGS` (array, appended by `log_warn`) and `FOLLOWUPS` (array). `test/helper.bash` produces `setup_common`, `teardown_common`, `stub_command NAME [EXIT] [STDOUT]`, `stub_called SUBSTRING`.

- [ ] **Step 1: Install dev tooling**

```bash
cd /home/alluo/dotfiles
brew install bats-core shellcheck shfmt
bats --version && shellcheck --version
```

- [ ] **Step 2: Write `Brewfile.dev`**

```ruby
# Development dependencies for working on this repo.
# NOT installed by install.sh — see Brewfile for runtime deps.
brew "bats-core"
brew "shellcheck"
brew "shfmt"
```

- [ ] **Step 3: Write `.gitignore`**

```gitignore
# OMC operational state
.omc/

# Per-host config — seeded from the .example files, never committed
home/.zshrc.local
claude/settings.local.json

# Claude Code machine state must never enter this repo
claude/.credentials.json
claude/history.jsonl
claude/projects/
claude/session-env/
claude/sessions/
claude/file-history/
claude/paste-cache/
claude/shell-snapshots/
claude/hud/cache/
claude/.claude.json

# Scratch
*.tmp
.DS_Store
```

- [ ] **Step 4: Write the failing test `test/log.bats`**

```bash
#!/usr/bin/env bats

load helper

setup() { setup_common; }
teardown() { teardown_common; }

@test "log_step writes a step marker to stderr" {
  run bash -c "source '$DOTFILES_ROOT/lib/log.sh'; log_step 'doing a thing' 2>&1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"doing a thing"* ]]
  [[ "$output" == *"▶"* ]]
}

@test "log_warn records the message in WARNINGS" {
  run bash -c "source '$DOTFILES_ROOT/lib/log.sh'; log_warn 'careful'; printf '%s\n' \"\${WARNINGS[@]}\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"careful"* ]]
}

@test "run executes the command when DRY_RUN is unset" {
  run bash -c "source '$DOTFILES_ROOT/lib/log.sh'; run touch '$TEST_TMP/made'; [ -f '$TEST_TMP/made' ]"
  [ "$status" -eq 0 ]
}

@test "run does not execute the command when DRY_RUN=1" {
  run bash -c "source '$DOTFILES_ROOT/lib/log.sh'; DRY_RUN=1 run touch '$TEST_TMP/nope'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TMP/nope" ]
}

@test "run under DRY_RUN reports what it would have done" {
  run bash -c "source '$DOTFILES_ROOT/lib/log.sh'; DRY_RUN=1 run touch /some/path 2>&1"
  [[ "$output" == *"touch /some/path"* ]]
}
```

- [ ] **Step 5: Write `test/helper.bash`**

```bash
# Shared bats setup. Sandboxes $HOME and allows stubbing external commands.

setup_common() {
  TEST_TMP="$(mktemp -d)"
  export TEST_TMP
  export HOME="$TEST_TMP/home"
  mkdir -p "$HOME"
  export STUB_BIN="$TEST_TMP/stubbin"
  mkdir -p "$STUB_BIN"
  export PATH="$STUB_BIN:$PATH"
  export STUB_LOG="$TEST_TMP/stub.log"
  : > "$STUB_LOG"
  DOTFILES_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export DOTFILES_ROOT
}

teardown_common() {
  [ -n "${TEST_TMP:-}" ] && rm -rf "$TEST_TMP"
}

# stub_command <name> [exit_code] [stdout]
# Creates a fake executable that logs its invocation to $STUB_LOG.
stub_command() {
  local name=$1 code=${2:-0} out=${3:-}
  cat > "$STUB_BIN/$name" <<EOF
#!/usr/bin/env bash
echo "$name \$*" >> "$STUB_LOG"
if [ -n '$out' ]; then printf '%s\n' '$out'; fi
exit $code
EOF
  chmod +x "$STUB_BIN/$name"
}

# stub_called <substring> — true if any stub invocation line contains it
stub_called() {
  grep -qF -- "$1" "$STUB_LOG"
}
```

- [ ] **Step 6: Run the test to verify it fails**

Run: `bats test/log.bats`
Expected: all 5 tests FAIL — `lib/log.sh` does not exist.

- [ ] **Step 7: Write `lib/log.sh`**

```bash
#!/usr/bin/env bash
# Logging and the dry-run wrapper. Sourced by install.sh, verify.sh, and every step.
# All output goes to stderr so callers can capture stdout for data.

WARNINGS=()
FOLLOWUPS=()

log_step() { printf '\n▶ %s\n' "$*" >&2; }
log_ok()   { printf '  ✓ %s\n' "$*" >&2; }
log_fail() { printf '  ✗ %s\n' "$*" >&2; }
log_dry()  { printf '  · would run: %s\n' "$*" >&2; }

log_warn() {
  printf '  ⚠ %s\n' "$*" >&2
  WARNINGS+=("$*")
}

log_followup() { FOLLOWUPS+=("$*"); }

# run CMD... — execute unless DRY_RUN=1
run() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    log_dry "$*"
    return 0
  fi
  "$@"
}
```

- [ ] **Step 8: Run the test to verify it passes**

Run: `bats test/log.bats`
Expected: 5 tests PASS.

- [ ] **Step 9: Verify shellcheck is clean**

Run: `shellcheck lib/log.sh`
Expected: no output, exit 0.

- [ ] **Step 10: Commit**

```bash
git add .gitignore Brewfile.dev lib/log.sh test/helper.bash test/log.bats
git commit -m "feat: add logging library and bats test harness"
```

---

### Task 2: OS and Homebrew detection

**Files:**
- Create: `lib/os.sh`
- Test: `test/os.bats`

**Interfaces:**
- Consumes: `lib/log.sh` (`log_warn`, `log_ok`, `run`).
- Produces: `detect_os` → prints `macos` or `linux`, returns 1 on anything else; `detect_arch` → prints `arm64` or `x86_64`; `brew_prefix` → prints the resolved prefix, returns 1 if no brew found; `ensure_homebrew` → returns 0 if brew present or successfully installed, 1 otherwise.

- [ ] **Step 1: Write the failing test `test/os.bats`**

```bash
#!/usr/bin/env bats

load helper

setup() { setup_common; }
teardown() { teardown_common; }

@test "detect_os returns macos on Darwin" {
  stub_command uname 0 "Darwin"
  run bash -c "source '$DOTFILES_ROOT/lib/log.sh'; source '$DOTFILES_ROOT/lib/os.sh'; detect_os"
  [ "$status" -eq 0 ]
  [ "$output" = "macos" ]
}

@test "detect_os returns linux on Linux" {
  stub_command uname 0 "Linux"
  run bash -c "source '$DOTFILES_ROOT/lib/log.sh'; source '$DOTFILES_ROOT/lib/os.sh'; detect_os"
  [ "$status" -eq 0 ]
  [ "$output" = "linux" ]
}

@test "detect_os fails on an unsupported kernel" {
  stub_command uname 0 "FreeBSD"
  run bash -c "source '$DOTFILES_ROOT/lib/log.sh'; source '$DOTFILES_ROOT/lib/os.sh'; detect_os"
  [ "$status" -eq 1 ]
}

@test "brew_prefix prefers Apple Silicon path when present" {
  mkdir -p "$TEST_TMP/opt/homebrew/bin"
  printf '#!/bin/sh\n' > "$TEST_TMP/opt/homebrew/bin/brew"
  chmod +x "$TEST_TMP/opt/homebrew/bin/brew"
  run bash -c "source '$DOTFILES_ROOT/lib/log.sh'; source '$DOTFILES_ROOT/lib/os.sh'; BREW_CANDIDATE_ROOT='$TEST_TMP' brew_prefix"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TMP/opt/homebrew" ]
}

@test "brew_prefix falls back to linuxbrew path" {
  mkdir -p "$TEST_TMP/home/linuxbrew/.linuxbrew/bin"
  printf '#!/bin/sh\n' > "$TEST_TMP/home/linuxbrew/.linuxbrew/bin/brew"
  chmod +x "$TEST_TMP/home/linuxbrew/.linuxbrew/bin/brew"
  run bash -c "source '$DOTFILES_ROOT/lib/log.sh'; source '$DOTFILES_ROOT/lib/os.sh'; BREW_CANDIDATE_ROOT='$TEST_TMP' brew_prefix"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TMP/home/linuxbrew/.linuxbrew" ]
}

@test "brew_prefix fails when no brew exists" {
  run bash -c "source '$DOTFILES_ROOT/lib/log.sh'; source '$DOTFILES_ROOT/lib/os.sh'; BREW_CANDIDATE_ROOT='$TEST_TMP/empty' brew_prefix"
  [ "$status" -eq 1 ]
}

@test "ensure_homebrew is a no-op when brew already resolves" {
  mkdir -p "$TEST_TMP/opt/homebrew/bin"
  printf '#!/bin/sh\n' > "$TEST_TMP/opt/homebrew/bin/brew"
  chmod +x "$TEST_TMP/opt/homebrew/bin/brew"
  stub_command curl 0
  run bash -c "source '$DOTFILES_ROOT/lib/log.sh'; source '$DOTFILES_ROOT/lib/os.sh'; BREW_CANDIDATE_ROOT='$TEST_TMP' ensure_homebrew"
  [ "$status" -eq 0 ]
  ! stub_called "curl"
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats test/os.bats`
Expected: all 7 FAIL — `lib/os.sh` does not exist.

- [ ] **Step 3: Write `lib/os.sh`**

```bash
#!/usr/bin/env bash
# OS/arch detection and Homebrew resolution.
#
# BREW_CANDIDATE_ROOT exists only so tests can point the probe at a sandbox.
# In real runs it is empty and the absolute paths below are used as-is.

detect_os() {
  case "$(uname -s)" in
    Darwin) printf 'macos\n' ;;
    Linux)  printf 'linux\n' ;;
    *)      log_fail "unsupported operating system: $(uname -s)"; return 1 ;;
  esac
}

detect_arch() {
  case "$(uname -m)" in
    arm64|aarch64) printf 'arm64\n' ;;
    *)             printf 'x86_64\n' ;;
  esac
}

# Probe order matters: Apple Silicon, Intel macOS, Linux.
brew_prefix() {
  local root="${BREW_CANDIDATE_ROOT:-}"
  local candidate
  for candidate in \
    "$root/opt/homebrew" \
    "$root/usr/local" \
    "$root/home/linuxbrew/.linuxbrew"
  do
    if [ -x "$candidate/bin/brew" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

ensure_homebrew() {
  if brew_prefix >/dev/null 2>&1; then
    log_ok "Homebrew present at $(brew_prefix)"
    return 0
  fi

  log_warn "Homebrew not found; bootstrapping"
  run /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    || { log_fail "Homebrew bootstrap failed"; return 1; }

  if [ "${DRY_RUN:-0}" = "1" ]; then
    return 0
  fi

  brew_prefix >/dev/null 2>&1 || {
    log_fail "Homebrew installed but no prefix resolved"
    return 1
  }
  log_ok "Homebrew installed at $(brew_prefix)"
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats test/os.bats`
Expected: 7 PASS.

- [ ] **Step 5: Verify shellcheck is clean**

Run: `shellcheck lib/os.sh`
Expected: no output, exit 0.

- [ ] **Step 6: Commit**

```bash
git add lib/os.sh test/os.bats
git commit -m "feat: add OS detection and Homebrew resolution"
```

---

### Task 3: Idempotent linking with backups

**Files:**
- Create: `lib/link.sh`
- Test: `test/link.bats`

**Interfaces:**
- Consumes: `lib/log.sh` (`log_ok`, `log_warn`, `run`).
- Produces: `backup_and_link SRC DEST` and `backup_and_copy SRC DEST`, both returning 0 on success and 1 on failure. Both read `$BACKUP_DIR`. `backup_and_link` is a no-op when `DEST` is already a symlink resolving to `SRC`.

This is the only code in the repo that writes to `$HOME`, so it carries the heaviest test burden.

- [ ] **Step 1: Write the failing test `test/link.bats`**

```bash
#!/usr/bin/env bats

load helper

setup() {
  setup_common
  export BACKUP_DIR="$TEST_TMP/backup"
  mkdir -p "$BACKUP_DIR"
  export SRC="$TEST_TMP/src"
  mkdir -p "$SRC"
  printf 'payload\n' > "$SRC/file"
}
teardown() { teardown_common; }

link_sh() {
  bash -c "source '$DOTFILES_ROOT/lib/log.sh'; source '$DOTFILES_ROOT/lib/link.sh'; $1"
}

@test "backup_and_link creates a symlink when destination is absent" {
  run link_sh "backup_and_link '$SRC/file' '$HOME/.file'"
  [ "$status" -eq 0 ]
  [ -L "$HOME/.file" ]
  [ "$(readlink -f "$HOME/.file")" = "$(readlink -f "$SRC/file")" ]
}

@test "backup_and_link creates missing parent directories" {
  run link_sh "backup_and_link '$SRC/file' '$HOME/.config/deep/nest/file'"
  [ "$status" -eq 0 ]
  [ -L "$HOME/.config/deep/nest/file" ]
}

@test "backup_and_link moves an existing regular file to the backup dir" {
  printf 'original\n' > "$HOME/.file"
  run link_sh "backup_and_link '$SRC/file' '$HOME/.file'"
  [ "$status" -eq 0 ]
  [ -L "$HOME/.file" ]
  [ "$(cat "$BACKUP_DIR/.file")" = "original" ]
}

@test "backup_and_link moves an existing directory to the backup dir" {
  mkdir -p "$HOME/.dir"
  printf 'inner\n' > "$HOME/.dir/inner"
  run link_sh "backup_and_link '$SRC' '$HOME/.dir'"
  [ "$status" -eq 0 ]
  [ -L "$HOME/.dir" ]
  [ "$(cat "$BACKUP_DIR/.dir/inner")" = "inner" ]
}

@test "backup_and_link is a no-op when the correct symlink already exists" {
  ln -s "$SRC/file" "$HOME/.file"
  run link_sh "backup_and_link '$SRC/file' '$HOME/.file'"
  [ "$status" -eq 0 ]
  [ -L "$HOME/.file" ]
  # nothing was backed up
  [ -z "$(ls -A "$BACKUP_DIR")" ]
}

@test "backup_and_link replaces a symlink pointing somewhere else" {
  printf 'other\n' > "$TEST_TMP/other"
  ln -s "$TEST_TMP/other" "$HOME/.file"
  run link_sh "backup_and_link '$SRC/file' '$HOME/.file'"
  [ "$status" -eq 0 ]
  [ "$(readlink -f "$HOME/.file")" = "$(readlink -f "$SRC/file")" ]
}

@test "backup_and_link fails when the source does not exist" {
  run link_sh "backup_and_link '$TEST_TMP/absent' '$HOME/.file'"
  [ "$status" -eq 1 ]
  [ ! -e "$HOME/.file" ]
}

@test "backup_and_link under DRY_RUN touches nothing" {
  run link_sh "DRY_RUN=1 backup_and_link '$SRC/file' '$HOME/.file'"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.file" ]
}

@test "backup_and_copy copies rather than links" {
  run link_sh "backup_and_copy '$SRC/file' '$HOME/.copied'"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.copied" ]
  [ ! -L "$HOME/.copied" ]
  [ "$(cat "$HOME/.copied")" = "payload" ]
}

@test "backup_and_copy overwrites an existing copy after backing it up" {
  printf 'stale\n' > "$HOME/.copied"
  run link_sh "backup_and_copy '$SRC/file' '$HOME/.copied'"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.copied")" = "payload" ]
  [ "$(cat "$BACKUP_DIR/.copied")" = "stale" ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats test/link.bats`
Expected: all 10 FAIL — `lib/link.sh` does not exist.

- [ ] **Step 3: Write `lib/link.sh`**

```bash
#!/usr/bin/env bash
# The only code that writes into $HOME. Everything is backed up before replacement.

# Move DEST aside into $BACKUP_DIR, preserving its basename.
_displace() {
  local dest=$1
  [ -e "$dest" ] || [ -L "$dest" ] || return 0
  run mkdir -p "$BACKUP_DIR"
  run mv "$dest" "$BACKUP_DIR/$(basename "$dest")"
  log_warn "moved existing $dest to $BACKUP_DIR/"
}

backup_and_link() {
  local src=$1 dest=$2

  if [ ! -e "$src" ]; then
    log_fail "link source missing: $src"
    return 1
  fi

  # Already correct — do nothing, so re-runs stay silent and cheap.
  if [ -L "$dest" ] && [ "$(readlink -f "$dest")" = "$(readlink -f "$src")" ]; then
    log_ok "$dest already linked"
    return 0
  fi

  _displace "$dest"
  run mkdir -p "$(dirname "$dest")"
  run ln -sfn "$src" "$dest" || { log_fail "could not link $dest"; return 1; }
  log_ok "linked $dest -> $src"
}

backup_and_copy() {
  local src=$1 dest=$2

  if [ ! -e "$src" ]; then
    log_fail "copy source missing: $src"
    return 1
  fi

  _displace "$dest"
  run mkdir -p "$(dirname "$dest")"
  if [ -d "$src" ]; then
    run cp -R "$src" "$dest" || { log_fail "could not copy $dest"; return 1; }
  else
    run cp "$src" "$dest" || { log_fail "could not copy $dest"; return 1; }
  fi
  log_ok "copied $dest"
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats test/link.bats`
Expected: 10 PASS.

- [ ] **Step 5: Verify shellcheck is clean**

Run: `shellcheck lib/link.sh`
Expected: no output, exit 0.

- [ ] **Step 6: Commit**

```bash
git add lib/link.sh test/link.bats
git commit -m "feat: add idempotent linking with automatic backups"
```

---

### Task 4: Installer entrypoint, flags, and dispatch

**Files:**
- Create: `install.sh`
- Test: `test/install.bats`

**Interfaces:**
- Consumes: `lib/log.sh`, `lib/os.sh`, `lib/link.sh`.
- Produces: an executable `install.sh` supporting `--dry-run`, `--only <step-id>`, `--skip-fonts`, `--help`. Exports `DOTFILES_ROOT`, `DRY_RUN`, `BACKUP_DIR`, `OS`, `ARCH` to the step functions. Defines `STEP_IDS` (ordered array of `id:function` pairs). Interprets each step function's return: 0 ok, 1 hard fail (abort, exit 1), 2 warn (continue).

Step scripts do not exist yet, so this task ships with stub step files that Tasks 5–11 replace. The stubs make the dispatcher testable now.

- [ ] **Step 1: Write the failing test `test/install.bats`**

```bash
#!/usr/bin/env bats

load helper

setup() {
  setup_common
  # Sandbox copy of the repo so stub steps can be swapped in freely.
  export REPO="$TEST_TMP/repo"
  mkdir -p "$REPO"
  cp -R "$DOTFILES_ROOT/lib" "$DOTFILES_ROOT/install.sh" "$REPO/"
  mkdir -p "$REPO/install"
}
teardown() { teardown_common; }

write_step() {  # write_step <file> <func> <return_code>
  cat > "$REPO/install/$1" <<EOF
#!/usr/bin/env bash
$2() { echo "ran $2" >> "$STUB_LOG"; return $3; }
EOF
}

@test "--help exits 0 and lists the flags" {
  run bash "$REPO/install.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--dry-run"* ]]
  [[ "$output" == *"--only"* ]]
  [[ "$output" == *"--skip-fonts"* ]]
}

@test "rejects an unknown flag" {
  run bash "$REPO/install.sh" --wat
  [ "$status" -ne 0 ]
  [[ "$output" == *"--wat"* ]]
}

@test "runs all steps in order" {
  write_step 00-preflight.sh step_preflight 0
  write_step 10-packages.sh step_packages 0
  run bash "$REPO/install.sh"
  [ "$status" -eq 0 ]
  stub_called "ran step_preflight"
  stub_called "ran step_packages"
}

@test "--only runs just the named step" {
  write_step 00-preflight.sh step_preflight 0
  write_step 10-packages.sh step_packages 0
  run bash "$REPO/install.sh" --only 10-packages
  [ "$status" -eq 0 ]
  ! stub_called "ran step_preflight"
  stub_called "ran step_packages"
}

@test "--only with an unknown step id fails" {
  write_step 00-preflight.sh step_preflight 0
  run bash "$REPO/install.sh" --only 99-nope
  [ "$status" -ne 0 ]
}

@test "a hard failure (return 1) aborts before later steps" {
  write_step 00-preflight.sh step_preflight 1
  write_step 10-packages.sh step_packages 0
  run bash "$REPO/install.sh"
  [ "$status" -eq 1 ]
  ! stub_called "ran step_packages"
}

@test "a warn (return 2) continues to later steps and still exits 0" {
  write_step 00-preflight.sh step_preflight 2
  write_step 10-packages.sh step_packages 0
  run bash "$REPO/install.sh"
  [ "$status" -eq 0 ]
  stub_called "ran step_packages"
}

@test "--skip-fonts skips the fonts step" {
  write_step 20-fonts.sh step_fonts 0
  run bash "$REPO/install.sh" --skip-fonts
  [ "$status" -eq 0 ]
  ! stub_called "ran step_fonts"
}

@test "--dry-run exports DRY_RUN=1 to steps" {
  cat > "$REPO/install/00-preflight.sh" <<'EOF'
#!/usr/bin/env bash
step_preflight() { echo "dry=${DRY_RUN:-0}" >> "$STUB_LOG"; return 0; }
EOF
  run bash "$REPO/install.sh" --dry-run
  [ "$status" -eq 0 ]
  stub_called "dry=1"
}

@test "summary lists the manual follow-ups" {
  write_step 00-preflight.sh step_preflight 0
  run bash "$REPO/install.sh"
  [[ "$output" == *"claude"* ]]
  [[ "$output" == *".zshrc.local"* ]]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats test/install.bats`
Expected: all 10 FAIL — `install.sh` does not exist.

- [ ] **Step 3: Write `install.sh`**

```bash
#!/usr/bin/env bash
# Entrypoint. Ordering and dispatch only — all real work lives in install/.
set -euo pipefail

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_ROOT

# shellcheck source=lib/log.sh
source "$DOTFILES_ROOT/lib/log.sh"
# shellcheck source=lib/os.sh
source "$DOTFILES_ROOT/lib/os.sh"
# shellcheck source=lib/link.sh
source "$DOTFILES_ROOT/lib/link.sh"

DRY_RUN=0
SKIP_FONTS=0
ONLY=""

# id:function, in execution order.
STEP_IDS=(
  "00-preflight:step_preflight"
  "10-packages:step_packages"
  "20-fonts:step_fonts"
  "30-zsh:step_zsh"
  "40-tmux:step_tmux"
  "50-nvim:step_nvim"
  "60-claude:step_claude"
  "70-skills:step_skills"
)

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

  --dry-run       Print what would happen without touching the filesystem
  --only <id>     Run a single step (e.g. --only 40-tmux)
  --skip-fonts    Skip font installation
  --help          Show this message

Steps run in order: 00-preflight 10-packages 20-fonts 30-zsh 40-tmux 50-nvim
                    60-claude 70-skills
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)    DRY_RUN=1 ;;
    --skip-fonts) SKIP_FONTS=1 ;;
    --only)       ONLY="${2:-}"; shift ;;
    --help|-h)    usage; exit 0 ;;
    *)            printf 'unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
export DRY_RUN

if [ -n "$ONLY" ]; then
  _known=0
  for pair in "${STEP_IDS[@]}"; do
    [ "${pair%%:*}" = "$ONLY" ] && _known=1
  done
  if [ "$_known" -eq 0 ]; then
    log_fail "unknown step id: $ONLY"
    exit 2
  fi
fi

BACKUP_DIR="$HOME/.dotfiles-backup/$(date -u +%Y-%m-%dT%H-%M-%SZ)"
export BACKUP_DIR

# Source whichever step files exist; missing ones are simply not run.
for f in "$DOTFILES_ROOT"/install/*.sh; do
  [ -e "$f" ] || continue
  # shellcheck source=/dev/null
  source "$f"
done

FAILED=""
RAN=()

for pair in "${STEP_IDS[@]}"; do
  id="${pair%%:*}"
  fn="${pair##*:}"

  [ -n "$ONLY" ] && [ "$ONLY" != "$id" ] && continue
  if [ "$id" = "20-fonts" ] && [ "$SKIP_FONTS" -eq 1 ]; then
    log_step "$id (skipped: --skip-fonts)"
    continue
  fi
  declare -F "$fn" >/dev/null 2>&1 || continue

  log_step "$id"
  set +e
  "$fn"
  rc=$?
  set -e

  case "$rc" in
    0) RAN+=("$id") ;;
    2) RAN+=("$id (with warnings)") ;;
    *) FAILED="$id"; break ;;
  esac
done

printf '\n──────── summary ────────\n' >&2
for r in "${RAN[@]:-}"; do
  [ -n "$r" ] && printf '  completed: %s\n' "$r" >&2
done

if [ "${#WARNINGS[@]}" -gt 0 ]; then
  printf '\n  warnings:\n' >&2
  for w in "${WARNINGS[@]}"; do printf '    ⚠ %s\n' "$w" >&2; done
fi

if [ -n "$FAILED" ]; then
  printf '\n  ✗ failed at step: %s\n' "$FAILED" >&2
  exit 1
fi

cat >&2 <<EOF

  next steps (not automatable):
    1. run 'claude' and log in — credentials are never packaged
    2. fill in ~/.zshrc.local with this machine's paths, licenses, and aliases
    3. if chsh was skipped, change your login shell manually (see warnings above)

  backups, if any, are in: $BACKUP_DIR
EOF
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats test/install.bats`
Expected: 10 PASS.

- [ ] **Step 5: Make it executable and shellcheck it**

```bash
chmod +x install.sh
shellcheck install.sh
```

Expected: no shellcheck output, exit 0.

- [ ] **Step 6: Commit**

```bash
git add install.sh test/install.bats
git commit -m "feat: add installer entrypoint with flags and step dispatch"
```

---

### Task 5: Preflight and package installation

**Files:**
- Create: `Brewfile`, `install/00-preflight.sh`, `install/10-packages.sh`
- Test: `test/preflight.bats`, `test/packages.bats`

**Interfaces:**
- Consumes: `log_step`/`log_ok`/`log_warn`/`log_fail`/`run`, `detect_os`, `detect_arch`, `ensure_homebrew`, `brew_prefix`, `$BACKUP_DIR`, `$DOTFILES_ROOT`.
- Produces: `step_preflight` (exports `OS` and `ARCH`, creates `$BACKUP_DIR`, returns 1 if `curl`/`git` missing or OS unsupported); `step_packages` (runs `brew bundle`, returns 1 on failure).

- [ ] **Step 1: Write `Brewfile`**

```ruby
# Runtime dependencies. Installed by install.sh on macOS and Linux alike.
brew "zsh"
brew "tmux"
brew "git"
brew "neovim"
brew "node"
```

- [ ] **Step 2: Write the failing test `test/preflight.bats`**

```bash
#!/usr/bin/env bats

load helper

setup() {
  setup_common
  export BACKUP_DIR="$TEST_TMP/backup"
}
teardown() { teardown_common; }

preflight() {
  bash -c "
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/os.sh'
    source '$DOTFILES_ROOT/install/00-preflight.sh'
    $1
  "
}

@test "step_preflight fails when curl is unavailable" {
  # A PATH containing only the stub dir hides curl and git.
  run bash -c "
    PATH='$STUB_BIN'
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/os.sh'
    source '$DOTFILES_ROOT/install/00-preflight.sh'
    step_preflight
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"curl"* ]]
}

@test "step_preflight fails on an unsupported OS" {
  stub_command uname 0 "FreeBSD"
  run preflight "step_preflight"
  [ "$status" -eq 1 ]
}

@test "step_preflight creates the backup directory" {
  stub_command uname 0 "Linux"
  stub_command brew 0
  run preflight "BREW_CANDIDATE_ROOT='' step_preflight"
  [ -d "$BACKUP_DIR" ]
}

@test "step_preflight exports OS and ARCH" {
  stub_command uname 0 "Linux"
  run preflight "step_preflight >/dev/null 2>&1; echo \"os=\$OS arch=\$ARCH\""
  [[ "$output" == *"os=linux"* ]]
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bats test/preflight.bats`
Expected: 4 FAIL — `install/00-preflight.sh` does not exist.

- [ ] **Step 4: Write `install/00-preflight.sh`**

```bash
#!/usr/bin/env bash
# Establish OS, required tooling, Homebrew, and the backup directory.

step_preflight() {
  local missing=0 cmd

  for cmd in curl git; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log_fail "required command not found: $cmd"
      missing=1
    fi
  done
  [ "$missing" -eq 0 ] || return 1

  OS="$(detect_os)" || return 1
  ARCH="$(detect_arch)"
  export OS ARCH
  log_ok "detected $OS/$ARCH"

  # Homebrew on RHEL needs a compiler and file(1) for anything without a bottle.
  if [ "$OS" = "linux" ]; then
    for cmd in gcc file; do
      command -v "$cmd" >/dev/null 2>&1 || \
        log_warn "$cmd missing — some brew formulae may fail to build (dnf install $cmd)"
    done
  fi

  run mkdir -p "$BACKUP_DIR"
  log_ok "backups will go to $BACKUP_DIR"

  ensure_homebrew || return 1
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bats test/preflight.bats`
Expected: 4 PASS.

- [ ] **Step 6: Write the failing test `test/packages.bats`**

```bash
#!/usr/bin/env bats

load helper

setup() { setup_common; }
teardown() { teardown_common; }

packages() {
  bash -c "
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/os.sh'
    export DOTFILES_ROOT='$DOTFILES_ROOT'
    source '$DOTFILES_ROOT/install/10-packages.sh'
    $1
  "
}

@test "step_packages invokes brew bundle with the repo Brewfile" {
  stub_command brew 0
  run packages "step_packages"
  [ "$status" -eq 0 ]
  stub_called "bundle"
  stub_called "$DOTFILES_ROOT/Brewfile"
}

@test "step_packages fails when brew bundle fails" {
  stub_command brew 1
  run packages "step_packages"
  [ "$status" -eq 1 ]
}

@test "step_packages under DRY_RUN does not call brew" {
  stub_command brew 0
  run packages "DRY_RUN=1 step_packages"
  [ "$status" -eq 0 ]
  ! stub_called "bundle"
}

@test "Brewfile lists every runtime dependency" {
  for pkg in zsh tmux git neovim node; do
    grep -q "brew \"$pkg\"" "$DOTFILES_ROOT/Brewfile"
  done
}

@test "Brewfile does not list dev-only tools" {
  ! grep -q "bats-core" "$DOTFILES_ROOT/Brewfile"
  ! grep -q "shellcheck" "$DOTFILES_ROOT/Brewfile"
  ! grep -q "fzf" "$DOTFILES_ROOT/Brewfile"
}
```

- [ ] **Step 7: Run the test to verify it fails**

Run: `bats test/packages.bats`
Expected: the 3 `step_packages` tests FAIL; the 2 Brewfile tests PASS (Brewfile was written in Step 1).

- [ ] **Step 8: Write `install/10-packages.sh`**

```bash
#!/usr/bin/env bash
# Install runtime dependencies from the Brewfile.

step_packages() {
  local brew_bin
  brew_bin="$(brew_prefix)/bin/brew"
  # In a sandboxed test there may be no real prefix; fall back to PATH.
  [ -x "$brew_bin" ] || brew_bin="brew"

  run "$brew_bin" bundle --file="$DOTFILES_ROOT/Brewfile" \
    || { log_fail "brew bundle failed"; return 1; }
  log_ok "runtime packages installed"
}
```

- [ ] **Step 9: Run the test to verify it passes**

Run: `bats test/packages.bats`
Expected: 5 PASS.

- [ ] **Step 10: Shellcheck both step scripts**

Run: `shellcheck install/00-preflight.sh install/10-packages.sh`
Expected: no output, exit 0.

- [ ] **Step 11: Commit**

```bash
git add Brewfile install/00-preflight.sh install/10-packages.sh \
        test/preflight.bats test/packages.bats
git commit -m "feat: add preflight checks and Brewfile package installation"
```

---

### Task 6: Font installation

**Files:**
- Create: `install/20-fonts.sh`
- Test: `test/fonts.bats`

**Interfaces:**
- Consumes: `log_*`, `run`, `$OS`, `$BACKUP_DIR`.
- Produces: `step_fonts` — returns 0 on success or when already installed, 2 on any download/extract problem (fonts are cosmetic; never hard-fail the install). Reads `NERD_FONTS_TAG` (default `v3.4.0`), overridable by the environment.

- [ ] **Step 1: Write the failing test `test/fonts.bats`**

```bash
#!/usr/bin/env bats

load helper

setup() { setup_common; }
teardown() { teardown_common; }

fonts() {
  bash -c "
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/install/20-fonts.sh'
    $1
  "
}

# Build a fake JetBrainsMono.zip that curl's stub will 'download'.
make_fake_zip() {
  local staging="$TEST_TMP/staging"
  mkdir -p "$staging"
  local i
  for i in $(seq 1 3); do
    printf 'fake\n' > "$staging/JetBrainsMonoNerdFont-$i.ttf"
  done
  (cd "$staging" && zip -q -r "$TEST_TMP/JetBrainsMono.zip" .)
}

@test "fonts land in ~/.local/share/fonts on linux" {
  make_fake_zip
  cat > "$STUB_BIN/curl" <<EOF
#!/usr/bin/env bash
echo "curl \$*" >> "$STUB_LOG"
# last arg after -o is the destination
dest=""
while [ \$# -gt 0 ]; do
  [ "\$1" = "-o" ] && dest="\$2"
  shift
done
cp "$TEST_TMP/JetBrainsMono.zip" "\$dest"
EOF
  chmod +x "$STUB_BIN/curl"
  stub_command fc-cache 0

  run fonts "OS=linux step_fonts"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.local/share/fonts/JetBrainsMonoNerdFont-1.ttf" ]
}

@test "fc-cache runs on linux" {
  make_fake_zip
  cat > "$STUB_BIN/curl" <<EOF
#!/usr/bin/env bash
dest=""
while [ \$# -gt 0 ]; do [ "\$1" = "-o" ] && dest="\$2"; shift; done
cp "$TEST_TMP/JetBrainsMono.zip" "\$dest"
EOF
  chmod +x "$STUB_BIN/curl"
  stub_command fc-cache 0
  run fonts "OS=linux step_fonts"
  stub_called "fc-cache"
}

@test "fonts land in ~/Library/Fonts on macos and fc-cache is not run" {
  make_fake_zip
  cat > "$STUB_BIN/curl" <<EOF
#!/usr/bin/env bash
dest=""
while [ \$# -gt 0 ]; do [ "\$1" = "-o" ] && dest="\$2"; shift; done
cp "$TEST_TMP/JetBrainsMono.zip" "\$dest"
EOF
  chmod +x "$STUB_BIN/curl"
  stub_command fc-cache 0

  run fonts "OS=macos step_fonts"
  [ "$status" -eq 0 ]
  [ -f "$HOME/Library/Fonts/JetBrainsMonoNerdFont-1.ttf" ]
  ! stub_called "fc-cache"
}

@test "step_fonts warns rather than failing when the download fails" {
  stub_command curl 22
  run fonts "OS=linux step_fonts"
  [ "$status" -eq 2 ]
}

@test "step_fonts is a no-op when the marker file matches the pinned tag" {
  mkdir -p "$HOME/.local/share/fonts"
  printf 'v3.4.0\n' > "$HOME/.local/share/fonts/.jetbrains-nerd-font-version"
  stub_command curl 0
  run fonts "OS=linux step_fonts"
  [ "$status" -eq 0 ]
  ! stub_called "curl"
}

@test "step_fonts under DRY_RUN downloads nothing" {
  stub_command curl 0
  run fonts "DRY_RUN=1 OS=linux step_fonts"
  [ "$status" -eq 0 ]
  ! stub_called "curl"
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats test/fonts.bats`
Expected: 6 FAIL — `install/20-fonts.sh` does not exist.

- [ ] **Step 3: Write `install/20-fonts.sh`**

```bash
#!/usr/bin/env bash
# Install JetBrainsMono Nerd Font from the pinned upstream release.
#
# A release zip is used on both operating systems rather than a Homebrew cask,
# because casks are macOS-only and one code path is less to keep in sync.

NERD_FONTS_TAG="${NERD_FONTS_TAG:-v3.4.0}"
NERD_FONT_ASSET="JetBrainsMono.zip"

_font_dir() {
  if [ "${OS:-linux}" = "macos" ]; then
    printf '%s\n' "$HOME/Library/Fonts"
  else
    printf '%s\n' "$HOME/.local/share/fonts"
  fi
}

step_fonts() {
  local dir marker url tmp
  dir="$(_font_dir)"
  marker="$dir/.jetbrains-nerd-font-version"

  if [ -f "$marker" ] && [ "$(cat "$marker")" = "$NERD_FONTS_TAG" ]; then
    log_ok "JetBrainsMono Nerd Font $NERD_FONTS_TAG already installed"
    return 0
  fi

  if [ "${DRY_RUN:-0}" = "1" ]; then
    log_dry "download $NERD_FONT_ASSET $NERD_FONTS_TAG into $dir"
    return 0
  fi

  url="https://github.com/ryanoasis/nerd-fonts/releases/download/$NERD_FONTS_TAG/$NERD_FONT_ASSET"
  tmp="$(mktemp -d)"

  if ! curl -fsSL -o "$tmp/$NERD_FONT_ASSET" "$url"; then
    rm -rf "$tmp"
    log_warn "font download failed ($url) — skipping fonts"
    return 2
  fi

  mkdir -p "$dir"
  if ! unzip -qo "$tmp/$NERD_FONT_ASSET" -d "$dir" 'JetBrainsMono*'; then
    rm -rf "$tmp"
    log_warn "font archive could not be extracted — skipping fonts"
    return 2
  fi
  rm -rf "$tmp"

  # fontconfig is Linux-only; macOS picks up ~/Library/Fonts with no cache step.
  if [ "${OS:-linux}" = "linux" ]; then
    if command -v fc-cache >/dev/null 2>&1; then
      fc-cache -f "$dir" >/dev/null 2>&1 || log_warn "fc-cache failed"
    else
      log_warn "fc-cache not found — fonts may not be visible until you log out"
    fi
  fi

  printf '%s\n' "$NERD_FONTS_TAG" > "$marker"
  log_ok "installed JetBrainsMono Nerd Font $NERD_FONTS_TAG ($(ls "$dir" | grep -c 'JetBrainsMono') files)"
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats test/fonts.bats`
Expected: 6 PASS.

- [ ] **Step 5: Shellcheck**

Run: `shellcheck install/20-fonts.sh`
Expected: no output, exit 0.

- [ ] **Step 6: Commit**

```bash
git add install/20-fonts.sh test/fonts.bats
git commit -m "feat: install pinned JetBrainsMono Nerd Font on both platforms"
```

---

### Task 7: zsh configuration and the shared/per-host split

**Files:**
- Create: `home/.zshrc`, `home/.zshenv`, `home/.zshrc.local.example`, `install/30-zsh.sh`
- Test: `test/zsh.bats`

**Interfaces:**
- Consumes: `log_*`, `run`, `backup_and_link`, `brew_prefix`, `$OS`, `$DOTFILES_ROOT`.
- Produces: `step_zsh` — links `.zshrc`/`.zshenv`, installs oh-my-zsh if absent, seeds `~/.zshrc.local` from the example when absent, attempts `chsh`. Returns 1 only if oh-my-zsh install or linking fails; a `chsh` failure yields 2.

This is the highest-risk task: the whole point of the split is that `.zshrc` must not error on a machine lacking the EDA toolchain.

- [ ] **Step 1: Write the failing test `test/zsh.bats`**

```bash
#!/usr/bin/env bats

load helper

setup() {
  setup_common
  export BACKUP_DIR="$TEST_TMP/backup"
  mkdir -p "$BACKUP_DIR"
}
teardown() { teardown_common; }

zsh_step() {
  bash -c "
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/os.sh'
    source '$DOTFILES_ROOT/lib/link.sh'
    export DOTFILES_ROOT='$DOTFILES_ROOT' BACKUP_DIR='$BACKUP_DIR'
    source '$DOTFILES_ROOT/install/30-zsh.sh'
    $1
  "
}

@test "shared .zshrc contains no machine-specific paths" {
  ! grep -qE '/mnt/c|Vivado|XILINX|QUESTA|MGLS|SALT_LICENSE|Zscaler|nvim-linux-x86_64' \
    "$DOTFILES_ROOT/home/.zshrc"
}

@test "shared .zshrc does not hardcode a Homebrew prefix" {
  ! grep -q '/home/linuxbrew/.linuxbrew/bin/brew shellenv' "$DOTFILES_ROOT/home/.zshrc"
}

@test "shared .zshrc sources .zshrc.local guarded" {
  grep -q 'zshrc.local' "$DOTFILES_ROOT/home/.zshrc"
  grep -qE '\[ -f "\$HOME/\.zshrc\.local" \]' "$DOTFILES_ROOT/home/.zshrc"
}

@test "shared .zshrc loads nvm exactly once" {
  [ "$(grep -c 'nvm.sh' "$DOTFILES_ROOT/home/.zshrc")" -eq 1 ]
}

@test ".zshenv guards the cargo env" {
  grep -qE '\[ -f "\$HOME/\.cargo/env" \]' "$DOTFILES_ROOT/home/.zshenv"
}

@test "the example per-host file carries the EDA config" {
  for needle in Vivado QUESTA_HOME XILINXD_LICENSE_FILE NODE_EXTRA_CA_CERTS ssh-agent; do
    grep -q "$needle" "$DOTFILES_ROOT/home/.zshrc.local.example"
  done
}

@test "the example per-host file carries the skip-permissions alias" {
  grep -q 'dangerously-skip-permissions' "$DOTFILES_ROOT/home/.zshrc.local.example"
}

@test "the shared .zshrc does NOT carry the skip-permissions alias" {
  ! grep -q 'dangerously-skip-permissions' "$DOTFILES_ROOT/home/.zshrc"
}

@test ".zshrc parses cleanly under zsh with no EDA tooling present" {
  if ! command -v zsh >/dev/null 2>&1; then skip "zsh not installed"; fi
  run zsh -n "$DOTFILES_ROOT/home/.zshrc"
  [ "$status" -eq 0 ]
}

@test "step_zsh links .zshrc and .zshenv into HOME" {
  mkdir -p "$HOME/.oh-my-zsh"        # pretend already installed
  stub_command chsh 0
  stub_command zsh 0
  run zsh_step "OS=linux step_zsh"
  [ -L "$HOME/.zshrc" ]
  [ -L "$HOME/.zshenv" ]
}

@test "step_zsh seeds .zshrc.local when absent" {
  mkdir -p "$HOME/.oh-my-zsh"
  stub_command chsh 0
  run zsh_step "OS=linux step_zsh"
  [ -f "$HOME/.zshrc.local" ]
  [ ! -L "$HOME/.zshrc.local" ]
}

@test "step_zsh does not clobber an existing .zshrc.local" {
  mkdir -p "$HOME/.oh-my-zsh"
  printf 'MY OWN CONFIG\n' > "$HOME/.zshrc.local"
  stub_command chsh 0
  run zsh_step "OS=linux step_zsh"
  [ "$(cat "$HOME/.zshrc.local")" = "MY OWN CONFIG" ]
}

@test "step_zsh warns but does not fail when chsh fails" {
  mkdir -p "$HOME/.oh-my-zsh"
  stub_command chsh 1
  run zsh_step "OS=linux step_zsh"
  [ "$status" -eq 2 ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats test/zsh.bats`
Expected: all 13 FAIL — none of the files exist.

- [ ] **Step 3: Write `home/.zshrc`**

```zsh
# Portable zsh configuration.
#
# Machine-specific config — license servers, EDA tool paths, corporate CA certs,
# per-host aliases — belongs in ~/.zshrc.local, which is sourced at the end and
# is never tracked in the dotfiles repo.

# --- Homebrew ---------------------------------------------------------------
# Must run before oh-my-zsh so brew's completions are on FPATH before compinit.
# Probe order: Apple Silicon, Intel macOS, Linux.
for _brew_candidate in \
  /opt/homebrew/bin/brew \
  /usr/local/bin/brew \
  /home/linuxbrew/.linuxbrew/bin/brew
do
  if [ -x "$_brew_candidate" ]; then
    eval "$("$_brew_candidate" shellenv zsh)"
    break
  fi
done
unset _brew_candidate

# --- oh-my-zsh --------------------------------------------------------------
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)
[ -f "$ZSH/oh-my-zsh.sh" ] && source "$ZSH/oh-my-zsh.sh"

# --- node -------------------------------------------------------------------
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"

# --- path -------------------------------------------------------------------
export PATH="$HOME/.local/bin:$PATH"

# --- per-host ---------------------------------------------------------------
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
```

- [ ] **Step 4: Write `home/.zshenv`**

```zsh
# Guarded: Rust may not be installed on every machine.
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
```

- [ ] **Step 5: Write `home/.zshrc.local.example`**

```zsh
# Per-host configuration. Copied to ~/.zshrc.local on first install and never
# tracked by git. Everything here is commented out — uncomment and correct the
# paths for the machine you are on.

# --- ssh-agent --------------------------------------------------------------
# Reuses a running agent instead of spawning one per shell (the original config
# ran `eval "$(ssh-agent -s)"` unconditionally, leaking an agent per tmux pane).
#
# Gotcha: `ssh-add -l` exits 1 when the agent is reachable but empty, and 2 when
# it is unreachable. Only 2 means we actually need a new agent.
# _ssh_agent_unreachable() { ssh-add -l >/dev/null 2>&1; [ $? -eq 2 ]; }
# if _ssh_agent_unreachable; then
#   _agent_env="$HOME/.ssh/agent.env"
#   [ -f "$_agent_env" ] && . "$_agent_env" >/dev/null
#   if _ssh_agent_unreachable; then
#     mkdir -p "$HOME/.ssh"
#     (umask 077; ssh-agent -s > "$_agent_env")
#     . "$_agent_env" >/dev/null
#   fi
#   unset _agent_env
# fi

# --- corporate network ------------------------------------------------------
# export NODE_EXTRA_CA_CERTS="/path/to/ZscalerRootCertificate-2048-SHA256.crt"

# --- Claude Code ------------------------------------------------------------
# Bypasses every permission prompt. Deliberately per-host: do not enable this
# on a shared or production machine.
# alias claude='claude --dangerously-skip-permissions'

# --- Questa / ModelSim ------------------------------------------------------
# export MGLS_LICENSE_FILE=1800@ir601
# export SALT_LICENSE_SERVER=1800@ir601
# export MTI_HOME="$HOME/altera/25.1std/questa_fe"
# export QUESTA_HOME="$MTI_HOME"
# export PATH="$QUESTA_HOME/bin:$QUESTA_HOME/linux_x86_64:$PATH"
# alias vsim='vsim -onfinish stop -voptargs=+acc -assertdebug'

# --- Xilinx / Vivado --------------------------------------------------------
# source "$HOME/2026.1/Vivado/settings64.sh"
# export FLEXLM_DIAGNOSTICS=3
# export XIL_CSE_LEGACY_LICENSE_LOOKUP=1
# export PILOT_BYPASS_INITIALIZATION_CHECK=1
# export XILINXD_LICENSE_FILE="$HOME/.Xilinx/Xilinx.lic"
# export XIL_LIC_BYPASS_VERSION_CHECK=1
# export XVV_ENABLE_NOLIC_MODE=1

# --- WSL-only shortcuts -----------------------------------------------------
# alias cdh='cd /mnt/c/Users/Albert\ Luo/Desktop'
# alias cds='cd /mnt/c/Users/Albert\ Luo/Desktop/serenon_cpld'
```

- [ ] **Step 6: Write `install/30-zsh.sh`**

```bash
#!/usr/bin/env bash
# oh-my-zsh, the portable zsh config, and the login-shell change.

OMZ_INSTALL_URL="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"

step_zsh() {
  local rc=0

  if [ -d "$HOME/.oh-my-zsh" ]; then
    log_ok "oh-my-zsh already present"
  else
    # KEEP_ZSHRC stops the installer writing its own .zshrc over ours.
    run env RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
      /bin/sh -c "$(curl -fsSL "$OMZ_INSTALL_URL")" \
      || { log_fail "oh-my-zsh install failed"; return 1; }
    log_ok "installed oh-my-zsh"
  fi

  backup_and_link "$DOTFILES_ROOT/home/.zshrc"  "$HOME/.zshrc"  || return 1
  backup_and_link "$DOTFILES_ROOT/home/.zshenv" "$HOME/.zshenv" || return 1

  # Seeded, not linked: this file is per-host and must stay editable in place.
  if [ -f "$HOME/.zshrc.local" ]; then
    log_ok "~/.zshrc.local already exists — left untouched"
  else
    run cp "$DOTFILES_ROOT/home/.zshrc.local.example" "$HOME/.zshrc.local"
    log_ok "seeded ~/.zshrc.local from the example"
    log_followup "fill in ~/.zshrc.local for this machine"
  fi

  _set_login_shell || rc=2
  return $rc
}

_set_login_shell() {
  local target
  target="$(brew_prefix 2>/dev/null)/bin/zsh"
  [ -x "$target" ] || target="$(command -v zsh 2>/dev/null || true)"

  if [ -z "$target" ]; then
    log_warn "zsh not found — cannot change login shell"
    return 1
  fi

  if [ "${SHELL:-}" = "$target" ]; then
    log_ok "login shell already $target"
    return 0
  fi

  # chsh requires the shell to be listed in /etc/shells.
  if ! grep -qxF "$target" /etc/shells 2>/dev/null; then
    if ! run sudo -n sh -c "printf '%s\n' '$target' >> /etc/shells" 2>/dev/null; then
      log_warn "could not add $target to /etc/shells (no passwordless sudo)"
      log_followup "add '$target' to /etc/shells, then run: chsh -s $target"
      return 1
    fi
  fi

  if run chsh -s "$target"; then
    log_ok "login shell set to $target"
    return 0
  fi

  # Common on LDAP-managed corporate hosts where chsh is disabled outright.
  log_warn "chsh failed — login shell unchanged"
  log_followup "run manually: chsh -s $target"
  log_followup "or add to ~/.bashrc: [ -z \"\$ZSH_VERSION\" ] && exec $target -l"
  return 1
}
```

- [ ] **Step 7: Run the test to verify it passes**

Run: `bats test/zsh.bats`
Expected: 13 PASS.

- [ ] **Step 8: Confirm the split holds by sourcing the shared config in isolation**

```bash
env -i HOME="$(mktemp -d)" PATH="/usr/bin:/bin" \
  zsh -c 'source '"$PWD"'/home/.zshrc; echo SHELL_OK'
```

Expected: prints `SHELL_OK` with no errors — proves `.zshrc` survives a machine with no oh-my-zsh, no brew, no nvm, and no EDA tools.

- [ ] **Step 9: Shellcheck**

Run: `shellcheck install/30-zsh.sh`
Expected: no output, exit 0. (`home/.zshrc` is zsh, not bash — do not shellcheck it.)

- [ ] **Step 10: Commit**

```bash
git add home/.zshrc home/.zshenv home/.zshrc.local.example \
        install/30-zsh.sh test/zsh.bats
git commit -m "feat: add portable zsh config with per-host override layer"
```

---

### Task 8: tmux configuration

**Files:**
- Create: `config/tmux/tmux.conf.local` (copied), `install/40-tmux.sh`
- Test: `test/tmux.bats`

**Interfaces:**
- Consumes: `log_*`, `run`, `backup_and_link`, `$DOTFILES_ROOT`.
- Produces: `step_tmux` — clones oh-my-tmux at the pinned commit, symlinks `~/.config/tmux/tmux.conf` to it, links `tmux.conf.local`, installs tpm and plugins under `~/.config/tmux/plugins`. Returns 1 on clone/link failure, 2 if plugin installation fails.

- [ ] **Step 1: Copy the live tmux config into the repo**

```bash
mkdir -p config/tmux
cp /home/alluo/.config/tmux/tmux.conf.local config/tmux/tmux.conf.local
wc -l config/tmux/tmux.conf.local   # expect 525
```

- [ ] **Step 2: Write the failing test `test/tmux.bats`**

```bash
#!/usr/bin/env bats

load helper

setup() {
  setup_common
  export BACKUP_DIR="$TEST_TMP/backup"
  mkdir -p "$BACKUP_DIR"
}
teardown() { teardown_common; }

tmux_step() {
  bash -c "
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/link.sh'
    export DOTFILES_ROOT='$DOTFILES_ROOT' BACKUP_DIR='$BACKUP_DIR'
    source '$DOTFILES_ROOT/install/40-tmux.sh'
    $1
  "
}

# git stub that materialises a directory instead of cloning
stub_git_clone() {
  cat > "$STUB_BIN/git" <<'EOF'
#!/usr/bin/env bash
echo "git $*" >> "$STUB_LOG"
if [ "$1" = "clone" ]; then
  dest="${@: -1}"
  mkdir -p "$dest"
  printf '# fake oh-my-tmux\n' > "$dest/.tmux.conf"
  mkdir -p "$dest/bin"
  printf '#!/bin/sh\nexit 0\n' > "$dest/bin/install_plugins"
  chmod +x "$dest/bin/install_plugins"
fi
exit 0
EOF
  chmod +x "$STUB_BIN/git"
}

@test "the vendored tmux.conf.local is the real 525-line config" {
  [ "$(wc -l < "$DOTFILES_ROOT/config/tmux/tmux.conf.local")" -eq 525 ]
  grep -q 'tmux_conf_theme_colour_1' "$DOTFILES_ROOT/config/tmux/tmux.conf.local"
}

@test "the vendored config enables the two expected plugins" {
  grep -q "set -g @plugin 'accessd/tmux-agent-indicator'" \
    "$DOTFILES_ROOT/config/tmux/tmux.conf.local"
  grep -q "set -g @plugin 'laktak/extrakto'" \
    "$DOTFILES_ROOT/config/tmux/tmux.conf.local"
}

@test "step_tmux clones oh-my-tmux at the pinned commit" {
  stub_git_clone
  run tmux_step "step_tmux"
  stub_called "af33f07"
}

@test "step_tmux symlinks tmux.conf and links tmux.conf.local" {
  stub_git_clone
  run tmux_step "step_tmux"
  [ -L "$HOME/.config/tmux/tmux.conf" ]
  [ -L "$HOME/.config/tmux/tmux.conf.local" ]
}

@test "step_tmux uses the XDG plugin path, never ~/.tmux/plugins" {
  stub_git_clone
  run tmux_step "step_tmux"
  [ -d "$HOME/.config/tmux/plugins/tpm" ]
  [ ! -d "$HOME/.tmux/plugins" ]
}

@test "step_tmux is idempotent on a second run" {
  stub_git_clone
  run tmux_step "step_tmux"
  [ "$status" -eq 0 ]
  run tmux_step "step_tmux"
  [ "$status" -eq 0 ]
  [ -L "$HOME/.config/tmux/tmux.conf" ]
}

@test "step_tmux under DRY_RUN clones nothing" {
  stub_git_clone
  run tmux_step "DRY_RUN=1 step_tmux"
  [ "$status" -eq 0 ]
  [ ! -d "$HOME/.config/tmux/plugins/tpm" ]
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bats test/tmux.bats`
Expected: the two vendored-config tests PASS (copied in Step 1); the five `step_tmux` tests FAIL.

- [ ] **Step 4: Write `install/40-tmux.sh`**

```bash
#!/usr/bin/env bash
# oh-my-tmux, the local override, tpm, and plugins.
#
# Everything lives under ~/.config/tmux (XDG). The source machine had tpm trees
# in both ~/.tmux/plugins and ~/.config/tmux/plugins; this standardises on the
# latter, which is where tmux.conf already lives.

OH_MY_TMUX_REPO="https://github.com/gpakosz/.tmux.git"
OH_MY_TMUX_COMMIT="af33f07"

step_tmux() {
  local omt="$HOME/.local/share/tmux/oh-my-tmux"
  local tmux_dir="$HOME/.config/tmux"
  local plugin_dir="$tmux_dir/plugins"

  if [ -d "$omt/.git" ]; then
    log_ok "oh-my-tmux already cloned"
  else
    run mkdir -p "$(dirname "$omt")"
    run git clone -q "$OH_MY_TMUX_REPO" "$omt" \
      || { log_fail "oh-my-tmux clone failed"; return 1; }
    run git -C "$omt" checkout -q "$OH_MY_TMUX_COMMIT" \
      || { log_fail "could not check out oh-my-tmux $OH_MY_TMUX_COMMIT"; return 1; }
    log_ok "cloned oh-my-tmux at $OH_MY_TMUX_COMMIT"
  fi

  run mkdir -p "$tmux_dir"
  backup_and_link "$omt/.tmux.conf" "$tmux_dir/tmux.conf" || return 1
  backup_and_link "$DOTFILES_ROOT/config/tmux/tmux.conf.local" \
                  "$tmux_dir/tmux.conf.local" || return 1

  if [ -d "$plugin_dir/tpm/.git" ] || [ -f "$plugin_dir/tpm/tpm" ]; then
    log_ok "tpm already present"
  else
    run mkdir -p "$plugin_dir"
    run git clone -q https://github.com/tmux-plugins/tpm "$plugin_dir/tpm" \
      || { log_fail "tpm clone failed"; return 1; }
    log_ok "cloned tpm"
  fi

  # tpm reads this to decide where plugins live.
  export TMUX_PLUGIN_MANAGER_PATH="$plugin_dir"
  if [ -x "$plugin_dir/tpm/bin/install_plugins" ]; then
    if ! run "$plugin_dir/tpm/bin/install_plugins"; then
      log_warn "tpm plugin install failed — run prefix+I inside tmux"
      return 2
    fi
    log_ok "tmux plugins installed"
  fi
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bats test/tmux.bats`
Expected: 7 PASS.

- [ ] **Step 6: Confirm the real config parses**

```bash
tmux -f config/tmux/tmux.conf.local new-session -d -s plancheck \
  && tmux kill-session -t plancheck && echo CONFIG_OK
```

Expected: prints `CONFIG_OK`.

- [ ] **Step 7: Shellcheck**

Run: `shellcheck install/40-tmux.sh`
Expected: no output, exit 0.

- [ ] **Step 8: Commit**

```bash
git add config/tmux/tmux.conf.local install/40-tmux.sh test/tmux.bats
git commit -m "feat: package oh-my-tmux config with XDG plugin path"
```

---

### Task 9: Neovim configuration

**Files:**
- Create: `config/nvim/` (copied), `install/50-nvim.sh`
- Test: `test/nvim.bats`

**Interfaces:**
- Consumes: `log_*`, `run`, `backup_and_link`, `$DOTFILES_ROOT`.
- Produces: `step_nvim` — links `~/.config/nvim` to the repo copy and runs `Lazy! restore`. Returns 1 on link failure, 2 if the headless nvim run fails.

- [ ] **Step 1: Copy the live nvim config into the repo**

```bash
mkdir -p config
cp -R /home/alluo/.config/nvim config/nvim
# Drop anything machine-generated; lazy-lock.json must be kept.
rm -rf config/nvim/.git
ls config/nvim            # expect: LICENSE README.md init.lua lazy-lock.json lua
test -f config/nvim/lazy-lock.json && echo LOCKFILE_OK
```

- [ ] **Step 2: Write the failing test `test/nvim.bats`**

```bash
#!/usr/bin/env bats

load helper

setup() {
  setup_common
  export BACKUP_DIR="$TEST_TMP/backup"
  mkdir -p "$BACKUP_DIR"
}
teardown() { teardown_common; }

nvim_step() {
  bash -c "
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/link.sh'
    export DOTFILES_ROOT='$DOTFILES_ROOT' BACKUP_DIR='$BACKUP_DIR'
    source '$DOTFILES_ROOT/install/50-nvim.sh'
    $1
  "
}

@test "the vendored nvim config carries the lazy lockfile" {
  [ -f "$DOTFILES_ROOT/config/nvim/lazy-lock.json" ]
  run jq -e 'type == "object"' "$DOTFILES_ROOT/config/nvim/lazy-lock.json"
  [ "$status" -eq 0 ]
}

@test "the vendored nvim config carries the custom tabline" {
  [ -f "$DOTFILES_ROOT/config/nvim/lua/albert/tabline.lua" ]
}

@test "the vendored nvim config has no machine-specific paths" {
  ! grep -rqE '/mnt/c|/home/alluo' "$DOTFILES_ROOT/config/nvim"
}

@test "step_nvim links ~/.config/nvim to the repo copy" {
  stub_command nvim 0
  run nvim_step "step_nvim"
  [ "$status" -eq 0 ]
  [ -L "$HOME/.config/nvim" ]
  [ -f "$HOME/.config/nvim/init.lua" ]
}

@test "step_nvim restores plugins from the lockfile rather than syncing" {
  stub_command nvim 0
  run nvim_step "step_nvim"
  stub_called "Lazy! restore"
  ! stub_called "Lazy! sync"
}

@test "step_nvim warns rather than failing when headless nvim fails" {
  stub_command nvim 1
  run nvim_step "step_nvim"
  [ "$status" -eq 2 ]
  [ -L "$HOME/.config/nvim" ]
}

@test "step_nvim under DRY_RUN does not invoke nvim" {
  stub_command nvim 0
  run nvim_step "DRY_RUN=1 step_nvim"
  [ "$status" -eq 0 ]
  ! stub_called "Lazy!"
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bats test/nvim.bats`
Expected: the 3 vendored-config tests PASS; the 4 `step_nvim` tests FAIL.

- [ ] **Step 4: Write `install/50-nvim.sh`**

```bash
#!/usr/bin/env bash
# Link the NvChad-based config and restore plugins at their pinned revisions.

step_nvim() {
  backup_and_link "$DOTFILES_ROOT/config/nvim" "$HOME/.config/nvim" || return 1

  # 'restore' honours lazy-lock.json; 'sync' would move plugins to latest and
  # silently drift this machine away from the packaged revisions.
  if ! run nvim --headless "+Lazy! restore" +qa; then
    log_warn "nvim plugin restore failed — open nvim and run :Lazy restore"
    return 2
  fi
  log_ok "nvim plugins restored from lazy-lock.json"
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bats test/nvim.bats`
Expected: 7 PASS.

- [ ] **Step 6: Shellcheck**

Run: `shellcheck install/50-nvim.sh`
Expected: no output, exit 0.

- [ ] **Step 7: Commit**

```bash
git add config/nvim install/50-nvim.sh test/nvim.bats
git commit -m "feat: package Neovim config with pinned plugin revisions"
```

---

### Task 10: Claude Code configuration

**Files:**
- Create: `claude/settings.json`, `claude/CLAUDE.md`, `claude/.omc-config.json.template`, `claude/settings.local.json.example`, `claude/hud/` (5 files), `install/60-claude.sh`
- Test: `test/claude.bats`

**Interfaces:**
- Consumes: `log_*`, `run`, `backup_and_link`, `backup_and_copy`, `$DOTFILES_ROOT`.
- Produces: `step_claude` — installs the Claude Code CLI if absent, links `settings.json`, `CLAUDE.md`, and `hud/`, renders `.omc-config.json` from the template with the real node path, seeds `settings.local.json`. Returns 1 if linking or template rendering fails, 2 if the CLI install fails.

- [ ] **Step 1: Copy the Claude config into the repo, excluding all machine state**

```bash
mkdir -p claude/hud/lib
cp /home/alluo/.claude/settings.json          claude/settings.json
cp /home/alluo/.claude/CLAUDE.md              claude/CLAUDE.md
cp /home/alluo/.claude/hud/omc-hud-cache.sh   claude/hud/
cp /home/alluo/.claude/hud/find-node.sh       claude/hud/
cp /home/alluo/.claude/hud/omc-hud.mjs        claude/hud/
cp /home/alluo/.claude/hud/lib/config-dir.sh  claude/hud/lib/
cp /home/alluo/.claude/hud/lib/config-dir.mjs claude/hud/lib/
chmod +x claude/hud/*.sh

# Sanity: no credentials or session state came along.
! test -e claude/.credentials.json && ! test -e claude/hud/cache && echo NO_STATE_OK
```

- [ ] **Step 2: Fix the agent-indicator hook paths in the copied settings**

The four hooks reference `/home/alluo/.tmux/plugins/tmux-agent-indicator`. Repoint them at the XDG location. Run:

```bash
sed -i 's#/home/alluo/.tmux/plugins/tmux-agent-indicator#$HOME/.config/tmux/plugins/tmux-agent-indicator#g' \
  claude/settings.json
jq -e . claude/settings.json >/dev/null && echo JSON_OK
grep -c 'config/tmux/plugins/tmux-agent-indicator' claude/settings.json   # expect 4
```

- [ ] **Step 3: Remove the per-host skip-permissions setting from shared settings**

```bash
jq 'del(.skipDangerousModePermissionPrompt)' claude/settings.json > claude/settings.json.tmp
mv claude/settings.json.tmp claude/settings.json
jq -e 'has("skipDangerousModePermissionPrompt") | not' claude/settings.json && echo REMOVED_OK
```

- [ ] **Step 4: Write `claude/.omc-config.json.template`**

Copy the live file and replace the absolute node path with a marker:

```bash
sed 's#"nodeBinary": "[^"]*"#"nodeBinary": "@@NODE_BINARY@@"#' \
  /home/alluo/.claude/.omc-config.json > claude/.omc-config.json.template
grep -q '@@NODE_BINARY@@' claude/.omc-config.json.template && echo TEMPLATE_OK
```

- [ ] **Step 5: Write `claude/settings.local.json.example`**

```json
{
  "_comment": "Per-host Claude Code settings. Copied to ~/.claude/settings.local.json on install and never tracked. Uncomment skipDangerousModePermissionPrompt only on a machine you fully control.",
  "permissions": {
    "allow": []
  }
}
```

- [ ] **Step 6: Write the failing test `test/claude.bats`**

```bash
#!/usr/bin/env bats

load helper

setup() {
  setup_common
  export BACKUP_DIR="$TEST_TMP/backup"
  mkdir -p "$BACKUP_DIR"
}
teardown() { teardown_common; }

claude_step() {
  bash -c "
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/link.sh'
    export DOTFILES_ROOT='$DOTFILES_ROOT' BACKUP_DIR='$BACKUP_DIR'
    source '$DOTFILES_ROOT/install/60-claude.sh'
    $1
  "
}

@test "packaged settings.json is valid JSON" {
  run jq -e . "$DOTFILES_ROOT/claude/settings.json"
  [ "$status" -eq 0 ]
}

@test "packaged settings.json points hooks at the XDG plugin path" {
  grep -q 'config/tmux/plugins/tmux-agent-indicator' "$DOTFILES_ROOT/claude/settings.json"
  ! grep -q '\.tmux/plugins/tmux-agent-indicator' "$DOTFILES_ROOT/claude/settings.json"
}

@test "packaged settings.json omits the skip-permissions bypass" {
  run jq -e 'has("skipDangerousModePermissionPrompt")' "$DOTFILES_ROOT/claude/settings.json"
  [ "$status" -ne 0 ]
}

@test "packaged settings.json keeps the model, statusline, and plugin set" {
  run jq -e '.model and .statusLine and .enabledPlugins' "$DOTFILES_ROOT/claude/settings.json"
  [ "$status" -eq 0 ]
}

@test "no credentials or session state is packaged" {
  [ ! -e "$DOTFILES_ROOT/claude/.credentials.json" ]
  [ ! -e "$DOTFILES_ROOT/claude/history.jsonl" ]
  [ ! -e "$DOTFILES_ROOT/claude/projects" ]
  [ ! -e "$DOTFILES_ROOT/claude/hud/cache" ]
}

@test "the omc template has no absolute node path" {
  grep -q '@@NODE_BINARY@@' "$DOTFILES_ROOT/claude/.omc-config.json.template"
  ! grep -q '/home/alluo/.nvm' "$DOTFILES_ROOT/claude/.omc-config.json.template"
}

@test "step_claude links settings.json, CLAUDE.md and hud" {
  stub_command claude 0 "1.0.0"
  stub_command npm 0
  stub_command node 0
  run claude_step "step_claude"
  [ -L "$HOME/.claude/settings.json" ]
  [ -L "$HOME/.claude/CLAUDE.md" ]
  [ -L "$HOME/.claude/hud" ]
}

@test "step_claude renders the node path into .omc-config.json" {
  stub_command claude 0 "1.0.0"
  stub_command npm 0
  stub_command node 0
  run claude_step "step_claude"
  [ -f "$HOME/.claude/.omc-config.json" ]
  ! grep -q '@@NODE_BINARY@@' "$HOME/.claude/.omc-config.json"
  run jq -e '.nodeBinary' "$HOME/.claude/.omc-config.json"
  [ "$status" -eq 0 ]
}

@test "step_claude seeds settings.local.json without clobbering it" {
  stub_command claude 0 "1.0.0"
  stub_command node 0
  printf '{"mine":true}\n' > "$TEST_TMP/keep.json"
  mkdir -p "$HOME/.claude"
  cp "$TEST_TMP/keep.json" "$HOME/.claude/settings.local.json"
  run claude_step "step_claude"
  run jq -e '.mine' "$HOME/.claude/settings.local.json"
  [ "$status" -eq 0 ]
}

@test "step_claude installs the CLI when absent" {
  stub_command npm 0
  stub_command node 0
  run claude_step "step_claude"
  stub_called "@anthropic-ai/claude-code"
}

@test "step_claude warns rather than failing when the CLI install fails" {
  stub_command npm 1
  stub_command node 0
  run claude_step "step_claude"
  [ "$status" -eq 2 ]
}
```

- [ ] **Step 7: Run the test to verify it fails**

Run: `bats test/claude.bats`
Expected: the 6 packaging tests PASS (Steps 1–5 did that work); the 5 `step_claude` tests FAIL.

- [ ] **Step 8: Write `install/60-claude.sh`**

```bash
#!/usr/bin/env bash
# Claude Code CLI and configuration.
#
# Plugins are not packaged: Claude Code installs them itself from the
# extraKnownMarketplaces entries in settings.json on first launch. hud/ IS
# packaged, because OMC's setup flow only creates it after first launch, which
# would leave statusLine pointing at a missing script on a fresh machine.

step_claude() {
  local rc=0 node_bin

  if command -v claude >/dev/null 2>&1; then
    log_ok "Claude Code already installed"
  elif ! run npm install -g @anthropic-ai/claude-code; then
    log_warn "Claude Code install failed — install it manually"
    rc=2
  else
    log_ok "installed Claude Code"
  fi

  run mkdir -p "$HOME/.claude"
  backup_and_link "$DOTFILES_ROOT/claude/settings.json" "$HOME/.claude/settings.json" || return 1
  backup_and_link "$DOTFILES_ROOT/claude/CLAUDE.md"     "$HOME/.claude/CLAUDE.md"     || return 1
  backup_and_link "$DOTFILES_ROOT/claude/hud"           "$HOME/.claude/hud"           || return 1

  node_bin="$(command -v node || true)"
  if [ -z "$node_bin" ]; then
    log_fail "node not found — cannot render .omc-config.json"
    return 1
  fi

  if [ "${DRY_RUN:-0}" = "1" ]; then
    log_dry "render .omc-config.json with nodeBinary=$node_bin"
  else
    sed "s#@@NODE_BINARY@@#$node_bin#" \
      "$DOTFILES_ROOT/claude/.omc-config.json.template" \
      > "$HOME/.claude/.omc-config.json" \
      || { log_fail "could not render .omc-config.json"; return 1; }
    log_ok "rendered .omc-config.json (node: $node_bin)"
  fi

  # Per-host, so seeded rather than linked.
  if [ -f "$HOME/.claude/settings.local.json" ]; then
    log_ok "~/.claude/settings.local.json already exists — left untouched"
  else
    run cp "$DOTFILES_ROOT/claude/settings.local.json.example" \
           "$HOME/.claude/settings.local.json"
    log_ok "seeded ~/.claude/settings.local.json"
  fi

  log_followup "run 'claude' and log in — credentials are never packaged"
  return $rc
}
```

- [ ] **Step 9: Run the test to verify it passes**

Run: `bats test/claude.bats`
Expected: 11 PASS.

- [ ] **Step 10: Shellcheck**

Run: `shellcheck install/60-claude.sh`
Expected: no output, exit 0.

- [ ] **Step 11: Commit**

```bash
git add claude install/60-claude.sh test/claude.bats
git commit -m "feat: package Claude Code settings, CLAUDE.md, and HUD"
```

---

### Task 11: Agent skills

**Files:**
- Create: `agents/skills/` (copied), `agents/.skill-lock.json` (copied), `agents/CLAUDE-SKILL-LINKS.txt` (generated), `install/70-skills.sh`
- Test: `test/skills.bats`

**Interfaces:**
- Consumes: `log_*`, `run`, `backup_and_copy`, `$DOTFILES_ROOT`.
- Produces: `step_skills` — copies the skills tree and lock file to `~/.agents/`, then creates `~/.claude/skills/<name>` → `~/.agents/skills/<name>` for each name in `CLAUDE-SKILL-LINKS.txt`. Returns 2 if any individual link fails; 1 only if the tree copy fails.

Background: all 61 skills come from GitHub upstreams (`mattpocock/skills` 29, firecrawl 30, `anthropics/skills` 1, `vercel-labs/skills` 1); none are locally authored. The whole tree is 820K, so it is vendored outright rather than re-fetched.

- [ ] **Step 1: Copy the skills tree and lock file**

```bash
mkdir -p agents
cp -R /home/alluo/.agents/skills agents/skills
cp /home/alluo/.agents/.skill-lock.json agents/.skill-lock.json
ls agents/skills | wc -l                                  # expect 61
jq -r '.skills | keys | length' agents/.skill-lock.json    # expect 61
du -sh agents/skills                                       # expect ~820K
```

- [ ] **Step 2: Generate the link manifest from the live machine**

```bash
ls /home/alluo/.claude/skills | sort > agents/CLAUDE-SKILL-LINKS.txt
wc -l < agents/CLAUDE-SKILL-LINKS.txt                      # expect 59
# pdf and find-skills are intentionally not linked into Claude Code
! grep -qx 'pdf' agents/CLAUDE-SKILL-LINKS.txt && \
! grep -qx 'find-skills' agents/CLAUDE-SKILL-LINKS.txt && echo MANIFEST_OK
```

- [ ] **Step 3: Write the failing test `test/skills.bats`**

```bash
#!/usr/bin/env bats

load helper

setup() {
  setup_common
  export BACKUP_DIR="$TEST_TMP/backup"
  mkdir -p "$BACKUP_DIR"
}
teardown() { teardown_common; }

skills_step() {
  bash -c "
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/link.sh'
    export DOTFILES_ROOT='$DOTFILES_ROOT' BACKUP_DIR='$BACKUP_DIR'
    source '$DOTFILES_ROOT/install/70-skills.sh'
    $1
  "
}

@test "all 61 skills are vendored" {
  [ "$(ls "$DOTFILES_ROOT/agents/skills" | wc -l)" -eq 61 ]
}

@test "the lock file covers every vendored skill" {
  run bash -c "
    jq -r '.skills | keys[]' '$DOTFILES_ROOT/agents/.skill-lock.json' | sort > '$TEST_TMP/lock'
    ls '$DOTFILES_ROOT/agents/skills' | sort > '$TEST_TMP/dirs'
    diff '$TEST_TMP/lock' '$TEST_TMP/dirs'
  "
  [ "$status" -eq 0 ]
}

@test "the link manifest names 59 skills" {
  [ "$(wc -l < "$DOTFILES_ROOT/agents/CLAUDE-SKILL-LINKS.txt")" -eq 59 ]
}

@test "the link manifest excludes pdf and find-skills" {
  ! grep -qx 'pdf' "$DOTFILES_ROOT/agents/CLAUDE-SKILL-LINKS.txt"
  ! grep -qx 'find-skills' "$DOTFILES_ROOT/agents/CLAUDE-SKILL-LINKS.txt"
}

@test "every name in the manifest exists in the vendored tree" {
  while read -r name; do
    [ -d "$DOTFILES_ROOT/agents/skills/$name" ] || {
      echo "missing: $name"; return 1
    }
  done < "$DOTFILES_ROOT/agents/CLAUDE-SKILL-LINKS.txt"
}

@test "every vendored skill has a SKILL.md" {
  local d
  for d in "$DOTFILES_ROOT"/agents/skills/*/; do
    [ -f "$d/SKILL.md" ] || { echo "no SKILL.md in $d"; return 1; }
  done
}

@test "step_skills copies the tree and lock file into ~/.agents" {
  run skills_step "step_skills"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.agents/.skill-lock.json" ]
  [ -d "$HOME/.agents/skills/caveman" ]
}

@test "step_skills creates the symlink farm in ~/.claude/skills" {
  run skills_step "step_skills"
  [ -L "$HOME/.claude/skills/caveman" ]
  [ -d "$HOME/.claude/skills/caveman" ]
  [ "$(ls "$HOME/.claude/skills" | wc -l)" -eq 59 ]
}

@test "step_skills does not link pdf or find-skills into Claude Code" {
  run skills_step "step_skills"
  [ ! -e "$HOME/.claude/skills/pdf" ]
  [ ! -e "$HOME/.claude/skills/find-skills" ]
  [ -d "$HOME/.agents/skills/pdf" ]
}

@test "step_skills is idempotent" {
  run skills_step "step_skills"
  [ "$status" -eq 0 ]
  run skills_step "step_skills"
  [ "$status" -eq 0 ]
  [ "$(ls "$HOME/.claude/skills" | wc -l)" -eq 59 ]
}

@test "step_skills under DRY_RUN creates nothing" {
  run skills_step "DRY_RUN=1 step_skills"
  [ "$status" -eq 0 ]
  [ ! -d "$HOME/.agents/skills" ]
}
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `bats test/skills.bats`
Expected: the 6 packaging tests PASS; the 5 `step_skills` tests FAIL.

- [ ] **Step 5: Write `install/70-skills.sh`**

```bash
#!/usr/bin/env bash
# Agent skills.
#
# ~/.claude/skills holds symlinks into ~/.agents/skills, a shared tree used by
# several agent CLIs. All 61 skills come from GitHub upstreams and none are
# locally authored, but no skill-manager CLI is guaranteed on the target host,
# so the 820K tree is vendored and copied rather than re-fetched.

step_skills() {
  local rc=0 agents_dir="$HOME/.agents" name target linkdir

  if [ "${DRY_RUN:-0}" = "1" ]; then
    log_dry "copy 61 skills into $agents_dir and link 59 into ~/.claude/skills"
    return 0
  fi

  mkdir -p "$agents_dir"
  # Copy contents rather than the directory, so re-runs refresh in place
  # instead of nesting skills/skills.
  mkdir -p "$agents_dir/skills"
  cp -R "$DOTFILES_ROOT/agents/skills/." "$agents_dir/skills/" \
    || { log_fail "could not copy skills tree"; return 1; }
  cp "$DOTFILES_ROOT/agents/.skill-lock.json" "$agents_dir/.skill-lock.json" \
    || { log_fail "could not copy .skill-lock.json"; return 1; }
  log_ok "installed $(ls "$agents_dir/skills" | wc -l | tr -d ' ') skills into $agents_dir/skills"

  linkdir="$HOME/.claude/skills"
  mkdir -p "$linkdir"
  while read -r name; do
    [ -n "$name" ] || continue
    target="$agents_dir/skills/$name"
    if [ ! -d "$target" ]; then
      log_warn "skill in manifest but not vendored: $name"
      rc=2
      continue
    fi
    ln -sfn "$target" "$linkdir/$name" || { log_warn "could not link skill $name"; rc=2; }
  done < "$DOTFILES_ROOT/agents/CLAUDE-SKILL-LINKS.txt"

  log_ok "linked $(ls "$linkdir" | wc -l | tr -d ' ') skills into ~/.claude/skills"
  return $rc
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `bats test/skills.bats`
Expected: 11 PASS.

- [ ] **Step 7: Shellcheck**

Run: `shellcheck install/70-skills.sh`
Expected: no output, exit 0.

- [ ] **Step 8: Commit**

```bash
git add agents install/70-skills.sh test/skills.bats
git commit -m "feat: vendor agent skills tree and recreate the symlink farm"
```

---

### Task 12: Verification script

**Files:**
- Create: `verify.sh`
- Test: `test/verify.bats`

**Interfaces:**
- Consumes: `lib/log.sh`.
- Produces: an executable `verify.sh` that runs every assertion, prints one line per check, and exits 0 only if all pass. Defines `check DESCRIPTION COMMAND...` which records pass/fail and never aborts early, so one failure does not hide the rest.

- [ ] **Step 1: Write the failing test `test/verify.bats`**

```bash
#!/usr/bin/env bats

load helper

setup() { setup_common; }
teardown() { teardown_common; }

@test "verify.sh exits non-zero on a machine with nothing installed" {
  run bash "$DOTFILES_ROOT/verify.sh"
  [ "$status" -ne 0 ]
}

@test "verify.sh reports every check rather than stopping at the first failure" {
  run bash "$DOTFILES_ROOT/verify.sh"
  # More than one check line must appear even though the first one failed.
  [ "$(printf '%s\n' "$output" | grep -c -E '✓|✗')" -gt 3 ]
}

@test "verify.sh names the specific thing that failed" {
  run bash "$DOTFILES_ROOT/verify.sh"
  [[ "$output" == *"zsh"* ]]
}

@test "check helper passes for a true command and fails for a false one" {
  run bash -c "
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/verify.sh' --source-only
    check 'true thing' true
    check 'false thing' false
    printf 'failures=%s\n' \"\$FAILURES\"
  "
  [[ "$output" == *"failures=1"* ]]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats test/verify.bats`
Expected: 4 FAIL — `verify.sh` does not exist.

- [ ] **Step 3: Write `verify.sh`**

```bash
#!/usr/bin/env bash
# Post-install assertions. Runnable standalone; exits 0 only if everything passes.
set -uo pipefail

VERIFY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
[ -n "${WARNINGS+x}" ] || source "$VERIFY_ROOT/lib/log.sh"

FAILURES=0

# check DESCRIPTION COMMAND... — never aborts, so one failure cannot mask others.
check() {
  local desc=$1
  shift
  if "$@" >/dev/null 2>&1; then
    printf '  ✓ %s\n' "$desc"
  else
    printf '  ✗ %s\n' "$desc"
    FAILURES=$((FAILURES + 1))
  fi
}

# Allow the bats test to source the helpers without running the suite.
case "${1:-}" in --source-only) return 0 2>/dev/null || exit 0 ;; esac

_link_count() { [ "$(ls "$HOME/.claude/skills" 2>/dev/null | wc -l | tr -d ' ')" -eq 59 ]; }
_font_count() {
  if [ "$(uname -s)" = "Darwin" ]; then
    [ "$(ls "$HOME/Library/Fonts" 2>/dev/null | grep -c JetBrainsMono)" -ge 90 ]
  else
    [ "$(fc-list 2>/dev/null | grep -c JetBrainsMono)" -ge 90 ]
  fi
}
_tmux_parses() {
  tmux -f "$HOME/.config/tmux/tmux.conf" new-session -d -s _verify_$$ \
    && tmux kill-session -t _verify_$$
}
_no_state_linked() {
  local p
  for p in .credentials.json history.jsonl projects session-env; do
    [ -L "$HOME/.claude/$p" ] && return 1
  done
  return 0
}
_omc_node_ok() {
  local n
  n="$(jq -r '.nodeBinary' "$HOME/.claude/.omc-config.json" 2>/dev/null)"
  [ -n "$n" ] && [ -x "$n" ]
}

printf '\n──────── shell ────────\n'
check "zsh is installed"                    command -v zsh
check "zsh starts an interactive shell cleanly" zsh -ic 'exit'
check "~/.zshrc is a symlink"               test -L "$HOME/.zshrc"
check "~/.zshrc.local exists"               test -f "$HOME/.zshrc.local"

printf '\n──────── tmux ────────\n'
check "tmux is installed"                   command -v tmux
check "~/.config/tmux/tmux.conf resolves"   test -e "$HOME/.config/tmux/tmux.conf"
check "tmux.conf.local is linked"           test -L "$HOME/.config/tmux/tmux.conf.local"
check "tmux config parses"                  _tmux_parses
check "tpm is installed (XDG path)"         test -d "$HOME/.config/tmux/plugins/tpm"
check "tmux-agent-indicator is installed"   test -d "$HOME/.config/tmux/plugins/tmux-agent-indicator"
check "extrakto is installed"               test -d "$HOME/.config/tmux/plugins/extrakto"

printf '\n──────── fonts ────────\n'
check "JetBrainsMono Nerd Font present"     _font_count

printf '\n──────── nvim ────────\n'
check "nvim is installed"                   command -v nvim
check "~/.config/nvim is linked"            test -L "$HOME/.config/nvim"
check "nvim starts headless cleanly"        nvim --headless +qa

printf '\n──────── claude code ────────\n'
check "claude CLI is installed"             command -v claude
check "settings.json is linked"             test -L "$HOME/.claude/settings.json"
check "settings.json is valid JSON"         jq -e . "$HOME/.claude/settings.json"
check "CLAUDE.md is linked"                 test -L "$HOME/.claude/CLAUDE.md"
check "hud script is executable"            test -x "$HOME/.claude/hud/omc-hud-cache.sh"
check ".omc-config.json node path is valid" _omc_node_ok
check "59 skills are linked"                _link_count
check "pdf is not linked into Claude Code"  test '!' -e "$HOME/.claude/skills/pdf"
check "no machine state is linked"          _no_state_linked

printf '\n'
if [ "$FAILURES" -eq 0 ]; then
  printf '✓ all checks passed\n'
  exit 0
fi
printf '✗ %s check(s) failed\n' "$FAILURES"
exit 1
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats test/verify.bats`
Expected: 4 PASS.

- [ ] **Step 5: Make it executable and shellcheck it**

```bash
chmod +x verify.sh
shellcheck verify.sh
```

Expected: no shellcheck output, exit 0.

- [ ] **Step 6: Commit**

```bash
git add verify.sh test/verify.bats
git commit -m "feat: add standalone post-install verification script"
```

---

### Task 13: Container integration test, README, and full-suite green

**Files:**
- Create: `test/Dockerfile.rocky9`, `test/run-container-test.sh`, `README.md`
- Modify: none

**Interfaces:**
- Consumes: everything built in Tasks 1–12.
- Produces: `test/run-container-test.sh` — builds the Rocky 9 image and runs `install.sh` then `verify.sh` inside it as a non-root sudo user; exits non-zero if either fails.

This is the task that proves the package actually works end to end on a RHEL-family host.

- [ ] **Step 1: Write `test/Dockerfile.rocky9`**

```dockerfile
# RHEL-family integration test target. Approximates a fresh corporate host:
# a non-root user with sudo, and none of the dotfiles dependencies preinstalled.
FROM rockylinux:9

RUN dnf -y install sudo git curl file procps-ng which findutils \
                   gcc make unzip fontconfig \
 && dnf clean all

RUN useradd -m -s /bin/bash tester \
 && echo 'tester ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/tester

USER tester
WORKDIR /home/tester
ENV HOME=/home/tester
```

- [ ] **Step 2: Write `test/run-container-test.sh`**

```bash
#!/usr/bin/env bash
# Build the Rocky 9 image and run a full install + verify inside it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="dotfiles-rocky9-test"

command -v docker >/dev/null 2>&1 || {
  printf 'docker is required for the container test\n' >&2
  exit 1
}

printf '▶ building %s\n' "$IMAGE"
docker build -q -t "$IMAGE" -f "$ROOT/test/Dockerfile.rocky9" "$ROOT/test"

printf '▶ running install.sh + verify.sh in the container\n'
docker run --rm \
  -v "$ROOT:/dotfiles:ro" \
  "$IMAGE" \
  bash -lc '
    set -euo pipefail
    cp -R /dotfiles ~/dotfiles
    cd ~/dotfiles
    ./install.sh
    ./verify.sh
  '
```

- [ ] **Step 3: Make it executable and run the dry-run path first**

```bash
chmod +x test/run-container-test.sh
./install.sh --dry-run
```

Expected: the plan prints, exit 0, and `git status --porcelain` shows no changes to `$HOME` — dry-run must touch nothing.

- [ ] **Step 4: Run the container test**

Run: `./test/run-container-test.sh`
Expected: install completes, `verify.sh` prints `✓ all checks passed`, exit 0.

If Homebrew bootstrap inside the container is slow, that is expected on first run — the image is not cached between `docker build` and `docker run`.

- [ ] **Step 5: Run the entire bats suite and shellcheck everything**

```bash
bats test/
shellcheck install.sh verify.sh lib/*.sh install/*.sh test/run-container-test.sh
```

Expected: all bats tests PASS; shellcheck silent, exit 0.

- [ ] **Step 6: Write `README.md`**

```markdown
# dotfiles

Portable tmux + zsh + Neovim + Claude Code setup for macOS and Red Hat Linux.

## Install

```bash
git clone <this repo> ~/dotfiles
cd ~/dotfiles
./install.sh
```

Then, because neither can be automated:

1. Run `claude` and log in. Credentials are never packaged.
2. Fill in `~/.zshrc.local` with this machine's paths, license servers, and aliases.

Preview without changing anything: `./install.sh --dry-run`.
Re-run one step: `./install.sh --only 40-tmux`.
Check an existing install: `./verify.sh`.

## What is shared and what is per-host

`~/.zshrc` is portable and tracked here. Everything machine-specific — EDA tool
paths, license servers, corporate CA certificates, WSL shortcuts, and the
`claude --dangerously-skip-permissions` alias — lives in `~/.zshrc.local`, which
is seeded from `home/.zshrc.local.example` and never tracked.

The same split applies to Claude Code: `settings.json` is shared,
`settings.local.json` is per-host.

## What gets installed

| Component | Detail |
|---|---|
| Dependencies | Homebrew on both platforms: zsh, tmux, git, neovim, node |
| Fonts | JetBrainsMono Nerd Font v3.4.0, all variants |
| zsh | oh-my-zsh, `robbyrussell`, `plugins=(git)` |
| tmux | oh-my-tmux pinned to `af33f07`, tpm, tmux-agent-indicator, extrakto |
| Neovim | NvChad v2.5, plugins restored from `lazy-lock.json` |
| Claude Code | CLI, `settings.json`, `CLAUDE.md`, OMC HUD, 61 skills (59 linked) |

Backups of anything displaced go to `~/.dotfiles-backup/<timestamp>/`.

## Tests

```bash
brew bundle --file=Brewfile.dev   # bats-core, shellcheck, shfmt
bats test/                        # unit tests
./test/run-container-test.sh      # full install on rockylinux:9
```

**macOS is not covered by an automated test** — no Mac is available to the
author. macOS support rests on shellcheck and review of the three
platform-divergent branches: Homebrew prefix, font destination, and whether
`fc-cache` runs. Use `--dry-run` on a Mac first.

## Never push

This repo has no remote by design.
```

- [ ] **Step 7: Commit**

```bash
git add test/Dockerfile.rocky9 test/run-container-test.sh README.md
git commit -m "test: add Rocky 9 integration test and document the package"
```

- [ ] **Step 8: Confirm no remote exists and nothing was pushed**

```bash
git remote -v            # expect empty output
git log --oneline | head -20
```

Expected: no remotes; the full task history present locally.

---

## Self-Review

**1. Spec coverage.** Walked each spec section against the plan:

| Spec item | Task |
|---|---|
| Repo layout | 1–13 (each file created in its owning task) |
| Three-layer config model | 7 (shared/per-host), 10 (Claude per-host) |
| `.zshrc` split, nvm dedup, dropped nvim PATH, brew prefix | 7 |
| ssh-agent rewrite | 7 (in `.zshrc.local.example`) |
| Machine state never packaged | 1 (`.gitignore`), 10 (test asserts it), 12 (`_no_state_linked`) |
| Vendored vs re-fetched Claude content | 10 |
| Skills revision (61 vendored, 59 linked) | 11 |
| tmux plugin dir collision fix | 8 (XDG path), 10 (hook paths) |
| `.omc-config.json` node path | 10 |
| HUD bootstrap-order fix | 10 |
| OS detection `macos`/`linux` | 2, 5 |
| Step table 00–70 | 5, 6, 7, 8, 9, 10, 11 |
| `Lazy! restore` not `sync` | 9 |
| Single font code path | 6 |
| `chsh` degradation | 7 |
| Idempotency | tested in 3, 8, 11; asserted per step |
| Dry-run | tested in 1, 3, 4, 6, 8, 9, 11, 13 |
| Output/summary format | 4 |
| Claude auth not automatable | 4, 10 |
| Verification assertions | 12 |
| Rocky 9 container test | 13 |
| macOS gap stated | 13 (README) |
| shellcheck everything | every task + 13 |

No gaps found.

**2. Placeholder scan.** No "TBD", "TODO", "implement later", "add error handling", or "similar to Task N". Every code step carries runnable content; test bodies are written out rather than described. The one deliberately generated artifact — `agents/CLAUDE-SKILL-LINKS.txt` — has its exact generating command and expected line count.

**3. Type and name consistency.** Checked across tasks:

- `log_step`/`log_ok`/`log_warn`/`log_fail`/`log_dry`/`log_followup`/`run` — defined in Task 1, used with those names in 2, 5–11.
- `detect_os`/`detect_arch`/`brew_prefix`/`ensure_homebrew` — defined in Task 2, used in 5 and 7.
- `backup_and_link`/`backup_and_copy`/`_displace` — defined in Task 3, used in 7–11.
- `step_preflight`/`step_packages`/`step_fonts`/`step_zsh`/`step_tmux`/`step_nvim`/`step_claude`/`step_skills` — the eight names in `STEP_IDS` (Task 4) match the eight function definitions in Tasks 5–11 exactly.
- `$BACKUP_DIR`, `$DOTFILES_ROOT`, `$DRY_RUN`, `$OS`, `$ARCH` — exported in Task 4/5, consumed under those names throughout.
- Return convention 0/1/2 — established in Task 4's dispatcher and honoured by every step.
- `check`/`FAILURES` — defined and used only in Task 12.

One inconsistency found and fixed while reviewing: `verify.sh` originally sourced `lib/log.sh` unconditionally, which broke the `--source-only` test path that sources it after `log.sh` is already loaded; it now guards with `[ -n "${WARNINGS+x}" ]`.
