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

  if [ "${DRY_RUN:-0}" = "1" ]; then
    log_dry "link tmux.conf and tmux.conf.local, install tpm and plugins"
    return 0
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
