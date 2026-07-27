#!/usr/bin/env bash
# context-manager: the daemon that hands a Claude Code session off to a fresh one
# before it exhausts its context window.
#
# Unlike every other step, this one builds from source: the daemon is Rust and
# lives in its own repo, so this step clones (or updates) it and delegates to its
# deploy/install.sh, which is the only thing that knows the full sequence —
# build, install binaries, wire the Claude hooks, enable the systemd user
# service. Duplicating that here would guarantee the two drift apart.
#
# Linux-only: the daemon runs as a systemd --user service, which macOS has no
# equivalent of. On macOS the step is a clean no-op.
#
# Config is SEEDED, not linked or copied over: config.toml is per-host
# (ignore_cwds holds machine-specific paths) and hand-tuned against a live
# machine, so clobbering it on every install would discard that tuning. Drift
# from the tracked copy is reported rather than silently corrected. It is seeded
# *before* delegating, so the upstream installer finds a config and does not
# write its own dry_run=true default over it.

CM_REPO_URL_DEFAULT="git@github.com:alberttluo/context-manager.git"

step_context_manager() {
  local rc=0
  local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/context-manager"
  local src="$DOTFILES_ROOT/config/context-manager/config.toml"
  local dest="$config_dir/config.toml"
  local repo_url="${CM_REPO_URL:-$CM_REPO_URL_DEFAULT}"
  local src_dir="${CM_SRC_DIR:-$HOME/src/context-manager}"
  local cargo_bin

  if [ "$(detect_os)" = "macos" ]; then
    log_ok "context-manager is Linux-only (systemd --user) — skipped"
    return 0
  fi

  # 1. Config -----------------------------------------------------------------
  if [ ! -f "$src" ]; then
    log_fail "tracked config missing: $src"
    return 1
  fi
  run mkdir -p "$config_dir"
  if [ -f "$dest" ]; then
    if cmp -s "$src" "$dest"; then
      log_ok "context-manager config matches the tracked copy"
    else
      log_warn "$dest differs from the tracked copy — left as-is (diff it and reconcile by hand)"
      rc=2
    fi
  else
    run cp "$src" "$dest"
    log_ok "seeded $dest"
  fi

  # 2. Toolchain --------------------------------------------------------------
  # rustup installs outside PATH for non-login shells, so probe ~/.cargo too.
  if command -v cargo >/dev/null 2>&1; then
    cargo_bin="$(command -v cargo)"
  elif [ -x "${CARGO_HOME:-$HOME/.cargo}/bin/cargo" ]; then
    cargo_bin="${CARGO_HOME:-$HOME/.cargo}/bin/cargo"
    PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
    export PATH
  else
    log_warn "cargo not found — cannot build context-manager"
    log_followup "install Rust (brew install rust, or https://rustup.rs) then: ./install.sh --only 80-context-manager"
    return 2
  fi
  log_ok "cargo found: $cargo_bin"

  # 3. Source ------------------------------------------------------------------
  if [ -d "$src_dir/.git" ]; then
    # --ff-only so local commits are never silently discarded; a diverged or
    # dirty checkout is reported and built as-is.
    if run git -C "$src_dir" pull --ff-only --quiet; then
      log_ok "updated $src_dir"
    else
      log_warn "could not fast-forward $src_dir — building the existing checkout"
      rc=2
    fi
  else
    run mkdir -p "$(dirname "$src_dir")"
    if ! run git clone --quiet "$repo_url" "$src_dir"; then
      log_fail "could not clone $repo_url"
      log_followup "clone context-manager manually to $src_dir, then: ./install.sh --only 80-context-manager"
      return 2
    fi
    log_ok "cloned $repo_url -> $src_dir"
  fi

  # 4. Build, install, and start ----------------------------------------------
  # Checked after the dry-run return: under DRY_RUN nothing was cloned, so the
  # deploy script legitimately is not there yet.
  if [ "${DRY_RUN:-0}" = "1" ]; then
    log_dry "bash $src_dir/deploy/install.sh (build + install binaries + systemd service)"
    return $rc
  fi
  if [ ! -f "$src_dir/deploy/install.sh" ]; then
    log_fail "$src_dir has no deploy/install.sh"
    return 1
  fi
  if ! bash "$src_dir/deploy/install.sh"; then
    log_fail "context-manager deploy/install.sh failed"
    return 2
  fi
  log_ok "context-manager built and deployed"

  if systemctl --user is-active --quiet context-manager 2>/dev/null; then
    log_ok "context-manager service is active"
  else
    log_warn "context-manager deployed but the service is not active"
    log_followup "systemctl --user status context-manager"
    rc=2
  fi

  return $rc
}
