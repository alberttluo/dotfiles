#!/usr/bin/env bats
#
# oh-my-tmux derives its config path as the first existing of:
#   $HOME/.tmux.conf, $XDG_CONFIG_HOME/tmux/tmux.conf, $HOME/.config/tmux/tmux.conf
# and then TMUX_CONF_LOCAL="$TMUX_CONF.local".
#
# So a leftover ~/.tmux.conf, or an XDG_CONFIG_HOME pointing somewhere other than
# ~/.config, silently shadows the packaged config: the theme never applies and the
# user is left with a stock-looking tmux while everything else installs fine.

load helper

setup() {
  setup_common
  export BACKUP_DIR="$TEST_TMP/backup"
  mkdir -p "$BACKUP_DIR"
  # git stub: materialise a fake oh-my-tmux instead of cloning
  cat > "$STUB_BIN/git" <<'EOF'
#!/usr/bin/env bash
echo "git $*" >> "$STUB_LOG"
if [ "$1" = "clone" ]; then
  for dest; do :; done
  mkdir -p "$dest/.git" "$dest/bin"
  printf '# fake oh-my-tmux\n' > "$dest/.tmux.conf"
  printf '#!/bin/sh\nexit 0\n' > "$dest/bin/install_plugins"
  chmod +x "$dest/bin/install_plugins"
fi
exit 0
EOF
  chmod +x "$STUB_BIN/git"
}
teardown() { teardown_common; }

tmux_step() {
  bash -c "
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/link.sh'
    export DOTFILES_ROOT='$DOTFILES_ROOT' BACKUP_DIR='$BACKUP_DIR'
    $1
    source '$DOTFILES_ROOT/install/40-tmux.sh'
    step_tmux
  "
}

# Replicates oh-my-tmux's derivation exactly.
derived_conf() {
  env HOME="$HOME" XDG_CONFIG_HOME="${1:-}" sh -c \
    'for c in "$HOME/.tmux.conf" "$XDG_CONFIG_HOME/tmux/tmux.conf" "$HOME/.config/tmux/tmux.conf"; do [ -f "$c" ] && printf "%s" "$c" && break; done'
}

@test "a legacy ~/.tmux.conf is moved aside so it cannot shadow the packaged config" {
  printf '# legacy config\n' > "$HOME/.tmux.conf"
  run tmux_step ":"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.tmux.conf" ]
  [ -f "$BACKUP_DIR/.tmux.conf" ]
  [ "$(cat "$BACKUP_DIR/.tmux.conf")" = "# legacy config" ]
}

@test "after install the derived TMUX_CONF_LOCAL exists" {
  printf '# legacy config\n' > "$HOME/.tmux.conf"
  run tmux_step ":"
  local conf
  conf="$(derived_conf "")"
  [ -n "$conf" ]
  [ -e "$conf.local" ]
}

@test "a legacy ~/.tmux.conf.local is also moved aside" {
  printf '# legacy config\n' > "$HOME/.tmux.conf"
  printf '# legacy local\n' > "$HOME/.tmux.conf.local"
  run tmux_step ":"
  [ ! -e "$HOME/.tmux.conf.local" ]
  [ -f "$BACKUP_DIR/.tmux.conf.local" ]
}

@test "install honours XDG_CONFIG_HOME instead of hardcoding ~/.config" {
  export XDG_CONFIG_HOME="$HOME/xdg"
  run tmux_step "export XDG_CONFIG_HOME='$HOME/xdg'"
  [ "$status" -eq 0 ]
  [ -L "$HOME/xdg/tmux/tmux.conf" ]
  [ -L "$HOME/xdg/tmux/tmux.conf.local" ]
  # and the derived path resolves to a config whose .local exists
  local conf
  conf="$(derived_conf "$HOME/xdg")"
  [ "$conf" = "$HOME/xdg/tmux/tmux.conf" ]
  [ -e "$conf.local" ]
}

@test "with XDG_CONFIG_HOME set, plugins go to the same XDG tmux dir" {
  run tmux_step "export XDG_CONFIG_HOME='$HOME/xdg'"
  [ -d "$HOME/xdg/tmux/plugins/tpm" ]
  [ ! -d "$HOME/.config/tmux/plugins/tpm" ]
}

@test "unset XDG_CONFIG_HOME still installs under ~/.config" {
  run tmux_step "unset XDG_CONFIG_HOME"
  [ -L "$HOME/.config/tmux/tmux.conf" ]
  [ -d "$HOME/.config/tmux/plugins/tpm" ]
}

@test "an existing correct install stays idempotent" {
  run tmux_step "unset XDG_CONFIG_HOME"
  [ "$status" -eq 0 ]
  run tmux_step "unset XDG_CONFIG_HOME"
  [ "$status" -eq 0 ]
  [ -L "$HOME/.config/tmux/tmux.conf" ]
}

# --- the verify.sh predicates that guard against this ------------------------

verify_pred() {  # verify_pred <predicate>
  bash -c "
    source '$DOTFILES_ROOT/lib/log.sh'
    VERIFY_ROOT='$DOTFILES_ROOT'
    source '$DOTFILES_ROOT/verify.sh' --source-only
    $1
  "
}

@test "verify _no_shadowing_tmux_conf fails when ~/.tmux.conf exists" {
  printf '# legacy\n' > "$HOME/.tmux.conf"
  run verify_pred "_no_shadowing_tmux_conf"
  [ "$status" -ne 0 ]
}

@test "verify _no_shadowing_tmux_conf passes when it does not" {
  run verify_pred "_no_shadowing_tmux_conf"
  [ "$status" -eq 0 ]
}

@test "verify _no_shadowing_tmux_conf fails for a dangling symlink too" {
  ln -s /nonexistent/target "$HOME/.tmux.conf"
  run verify_pred "_no_shadowing_tmux_conf"
  [ "$status" -ne 0 ]
}

@test "verify _tmux_conf_local_resolves fails when the .local sibling is missing" {
  printf '# legacy\n' > "$HOME/.tmux.conf"   # wins the search, has no .local
  run verify_pred "_tmux_conf_local_resolves"
  [ "$status" -ne 0 ]
}

@test "verify _tmux_conf_local_resolves passes after a correct install" {
  run tmux_step "unset XDG_CONFIG_HOME"
  run verify_pred "unset XDG_CONFIG_HOME; TMUX_DIR=\"\$HOME/.config/tmux\"; _tmux_conf_local_resolves"
  [ "$status" -eq 0 ]
}
