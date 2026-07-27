# Written by install.sh --data-root, and absent on a machine that keeps everything
# under $HOME. Must come first: it defines where the rest of this looks.
[ -f "$HOME/.dotfiles-env" ] && . "$HOME/.dotfiles-env"

# Guarded: Rust may not be installed on every machine.
[ -f "${CARGO_HOME:-$HOME/.cargo}/env" ] && . "${CARGO_HOME:-$HOME/.cargo}/env"
