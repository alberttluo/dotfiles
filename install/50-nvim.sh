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
