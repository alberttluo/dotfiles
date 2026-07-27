#!/usr/bin/env bash
# oh-my-zsh, the portable zsh config, and the login-shell change.

OMZ_INSTALL_URL="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"

step_zsh() {
  local rc=0

  if [ -d "${ZSH:-$HOME/.oh-my-zsh}" ]; then
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
    log_ok "$HOME/.zshrc.local already exists — left untouched"
  else
    run cp "$DOTFILES_ROOT/home/.zshrc.local.example" "$HOME/.zshrc.local"
    log_ok "seeded $HOME/.zshrc.local from the example"
    log_followup "fill in $HOME/.zshrc.local for this machine"
  fi

  _set_login_shell || rc=2
  return $rc
}

_set_login_shell() {
  local target prefix
  prefix="$(brew_prefix 2>/dev/null || true)"
  target="$prefix/bin/zsh"
  if [ -z "$prefix" ] || [ ! -x "$target" ]; then
    target="$(command -v zsh 2>/dev/null || true)"
  fi

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
