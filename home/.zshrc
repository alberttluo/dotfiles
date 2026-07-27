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
# Defaults only: ~/.dotfiles-env may already have pointed these at another volume.
: "${ZSH:=$HOME/.oh-my-zsh}"
export ZSH
ZSH_THEME="robbyrussell"
plugins=(git)
[ -f "$ZSH/oh-my-zsh.sh" ] && source "$ZSH/oh-my-zsh.sh"

# --- node -------------------------------------------------------------------
: "${NVM_DIR:=$HOME/.nvm}"
export NVM_DIR
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"

# --- path -------------------------------------------------------------------
export PATH="${PORTABLE_PREFIX:-$HOME/.local}/bin:$PATH"

# --- per-host ---------------------------------------------------------------
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
