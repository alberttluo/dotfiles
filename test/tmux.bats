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
  for dest; do :; done
  mkdir -p "$dest"
  printf '# fake oh-my-tmux\n' > "$dest/.tmux.conf"
  mkdir -p "$dest/.git" "$dest/bin"
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
