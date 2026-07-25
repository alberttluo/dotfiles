#!/usr/bin/env bash
# context-manager configuration.
#
# The binaries (context-managerd, cm-hook) are built from the separate
# context-manager repo and are deliberately NOT packaged here — they need a Rust
# toolchain and a release build, and this repo installs no compiled artifacts.
# The SessionStart/SessionEnd hooks that feed the daemon already ship in
# claude/settings.json, so only the config file is this step's business.
#
# SEEDED, not linked or copied over: config.toml is per-host (ignore_cwds holds
# machine-specific paths) and hand-tuned against a live machine, so clobbering it
# on every install would discard that tuning. Drift from the tracked copy is
# reported rather than silently corrected.

step_context_manager() {
  local rc=0 config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/context-manager"
  local src="$DOTFILES_ROOT/config/context-manager/config.toml"
  local dest="$config_dir/config.toml"

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

  # The daemon is optional: report what is missing instead of failing the install.
  if ! [ -x "$HOME/.local/bin/context-managerd" ] || ! [ -x "$HOME/.local/bin/cm-hook" ]; then
    log_warn "context-manager binaries not installed in ~/.local/bin"
    log_followup "build context-manager and run its deploy/install.sh to enable automatic handoffs"
  elif ! systemctl --user is-active --quiet context-manager 2>/dev/null; then
    log_warn "context-manager binaries present but the service is not active"
    log_followup "systemctl --user enable --now context-manager"
  else
    log_ok "context-manager service is active"
  fi

  return $rc
}
