#!/usr/bin/env bash
# context-manager: the daemon that hands a Claude Code session off to a fresh one
# before it exhausts its context window.
#
# Unlike every other step, this one builds from source: the daemon is Rust and
# lives in its own repo, vendored here as the submodule vendor/context-manager.
# The step delegates to its deploy/install.sh, which is the only thing that knows
# the full sequence — build, install binaries, wire the Claude hooks, enable the
# systemd user service. Duplicating that here would guarantee the two drift apart.
#
# A submodule rather than a clone into ~/src so the daemon a given dotfiles
# commit installs is pinned by that commit, and `git clone --recursive` is the
# whole install. Updating the daemon is therefore a deliberate act — `git
# submodule update --remote vendor/context-manager` and commit the new pin — not
# something an install silently does underneath you.
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

CM_SUBMODULE_PATH="vendor/context-manager"

step_context_manager() {
  local rc=0
  local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/context-manager"
  local src="$DOTFILES_ROOT/config/context-manager/config.toml"
  local dest="$config_dir/config.toml"
  local src_dir="$DOTFILES_ROOT/$CM_SUBMODULE_PATH"
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
  # A plain (non-recursive) clone leaves the submodule directory empty, so check
  # for real content rather than the directory itself. Already-populated is the
  # common case and must stay silent — the pin is whatever the dotfiles commit
  # says, and this step deliberately does not move it.
  if [ ! -e "$src_dir/deploy/install.sh" ]; then
    if ! run git -C "$DOTFILES_ROOT" submodule update --init --quiet -- "$CM_SUBMODULE_PATH"; then
      log_fail "could not check out the $CM_SUBMODULE_PATH submodule"
      log_followup "git -C $DOTFILES_ROOT submodule update --init -- $CM_SUBMODULE_PATH, then: ./install.sh --only 80-context-manager"
      return 2
    fi
    log_ok "checked out $CM_SUBMODULE_PATH"
  else
    log_ok "$CM_SUBMODULE_PATH is present at its pinned commit"
  fi

  # 4. Build, install, and start ----------------------------------------------
  # Checked after the dry-run return: under DRY_RUN the submodule was never
  # checked out, so the deploy script legitimately may not be there yet.
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
