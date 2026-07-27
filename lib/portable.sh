#!/usr/bin/env bash
# Provision runtime tools without a package manager and without sudo.
#
# Homebrew needs root to create its prefix, so on a locked-down host it is simply
# unavailable. Everything here fetches an upstream prebuilt binary into a
# user-writable prefix (~/.local by default), which is already on PATH via
# home/.zshrc.
#
# Not everything can be obtained this way. `git` has no official static build and
# is needed to clone this repo in the first place, so it is never claimed as
# fetchable. tmux ships no official static binary either; the Linux AppImage is
# used and extracted rather than mounted, so no FUSE is required, and there is no
# macOS equivalent.
#
# Versions are pinned. Bump deliberately: an unpinned "latest" turns every install
# into a different machine.

NVIM_VERSION="${NVIM_VERSION:-v0.12.4}"
NODE_VERSION="${NODE_VERSION:-v22.11.0}"
JQ_VERSION="${JQ_VERSION:-1.7.1}"
TMUX_APPIMAGE_VERSION="${TMUX_APPIMAGE_VERSION:-3.5a}"

portable_prefix() { printf '%s\n' "${PORTABLE_PREFIX:-$HOME/.local}"; }
portable_bin() { printf '%s\n' "$(portable_prefix)/bin"; }

# Passwordless sudo only. Prompting would hang an unattended install, and a host
# that needs a password is treated the same as one with no sudo at all.
have_sudo() {
  command -v sudo >/dev/null 2>&1 || return 1
  sudo -n true >/dev/null 2>&1
}

# fetch_to DEST URL — curl or wget, whichever exists.
fetch_to() {
  local dest=$1 url=$2
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$dest" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$dest" "$url"
  else
    log_fail "need curl or wget to download $url"
    return 1
  fi
}

# Map this machine to the naming each upstream uses.
_arch_alias() {
  case "$1:${ARCH:-x86_64}" in
    nvim:arm64)  printf 'arm64' ;;
    nvim:*)      printf 'x86_64' ;;
    node:arm64)  printf 'arm64' ;;
    node:*)      printf 'x64' ;;
    jq:arm64)    printf 'arm64' ;;
    jq:*)        printf 'amd64' ;;
  esac
}

portable_supported() {
  case "$1" in
    nvim|node|jq|zsh|rust) return 0 ;;
    # AppImage is Linux-only and there is no macOS static tmux to fall back on.
    tmux) [ "${OS:-linux}" = "linux" ] ;;
    *) return 1 ;;
  esac
}

portable_install() {
  local tool=$1

  if ! portable_supported "$tool"; then
    log_fail "no prebuilt download is available for $tool on ${OS:-linux}"
    return 1
  fi

  # rust installs into ~/.cargo, not the prefix, so it has its own presence check.
  if [ "$tool" != "rust" ] && [ -x "$(portable_bin)/$tool" ]; then
    log_ok "$tool already present in $(portable_bin)"
    return 0
  fi
  if [ "$tool" = "rust" ] && { command -v cargo >/dev/null 2>&1 || [ -x "${CARGO_HOME:-$HOME/.cargo}/bin/cargo" ]; }; then
    log_ok "cargo already present"
    return 0
  fi

  if [ "${DRY_RUN:-0}" = "1" ]; then
    log_dry "download $tool into $(portable_prefix)"
    return 0
  fi

  mkdir -p "$(portable_bin)"
  "_portable_$tool" || { log_fail "could not install $tool"; return 1; }
  log_ok "installed $tool into $(portable_bin)"
}

# Download into a scratch dir so a failed or partial fetch never lands on PATH.
_with_tmp() {
  local fn=$1 tmp rc
  tmp="$(mktemp -d)"
  "$fn" "$tmp"
  rc=$?
  rm -rf "$tmp"
  return $rc
}

_portable_jq() { _with_tmp _do_jq; }
_do_jq() {
  local tmp=$1 os_alias
  [ "${OS:-linux}" = "macos" ] && os_alias="macos" || os_alias="linux"
  fetch_to "$tmp/jq" \
    "https://github.com/jqlang/jq/releases/download/jq-$JQ_VERSION/jq-$os_alias-$(_arch_alias jq)" || return 1
  chmod +x "$tmp/jq"
  mv "$tmp/jq" "$(portable_bin)/jq"
}

_portable_nvim() { _with_tmp _do_nvim; }
_do_nvim() {
  local tmp=$1 os_alias name
  [ "${OS:-linux}" = "macos" ] && os_alias="macos" || os_alias="linux"
  name="nvim-$os_alias-$(_arch_alias nvim)"
  fetch_to "$tmp/nvim.tar.gz" \
    "https://github.com/neovim/neovim/releases/download/$NVIM_VERSION/$name.tar.gz" || return 1
  tar xzf "$tmp/nvim.tar.gz" -C "$tmp" || return 1
  # Ship the whole tree: nvim needs its runtime/ directory beside the binary.
  rm -rf "$(portable_prefix)/nvim"
  mkdir -p "$(portable_prefix)"
  mv "$tmp/$name" "$(portable_prefix)/nvim" || return 1
  ln -sfn "$(portable_prefix)/nvim/bin/nvim" "$(portable_bin)/nvim"
}

_portable_node() { _with_tmp _do_node; }
_do_node() {
  local tmp=$1 os_alias name ext
  if [ "${OS:-linux}" = "macos" ]; then os_alias="darwin"; ext="tar.gz"; else os_alias="linux"; ext="tar.xz"; fi
  name="node-$NODE_VERSION-$os_alias-$(_arch_alias node)"
  fetch_to "$tmp/node.$ext" "https://nodejs.org/dist/$NODE_VERSION/$name.$ext" || return 1
  tar xf "$tmp/node.$ext" -C "$tmp" || return 1
  rm -rf "$(portable_prefix)/node"
  mv "$tmp/$name" "$(portable_prefix)/node" || return 1
  local b
  for b in node npm npx; do
    [ -e "$(portable_prefix)/node/bin/$b" ] && ln -sfn "$(portable_prefix)/node/bin/$b" "$(portable_bin)/$b"
  done
  return 0
}

# romkatv/zsh-bin publishes self-contained zsh builds; its installer is the
# supported way to consume them and already targets a user prefix.
#
# -e no is REQUIRED, not cosmetic. The default is -e ask, which stops to ask
# whether to add the new zsh to /etc/shells and blocks forever on a prompt when
# there is no stdin. Writing /etc/shells also needs root, which is the whole thing
# we are avoiding here.
#
# -a sha256 makes the installer abort unless it can verify the download; this is an
# executable shell, so an unverified fetch is not acceptable.
_portable_zsh() { _with_tmp _do_zsh; }
_do_zsh() {
  local tmp=$1
  fetch_to "$tmp/install" "https://raw.githubusercontent.com/romkatv/zsh-bin/master/install" || return 1
  sh "$tmp/install" -q -e no -a sha256 -d "$(portable_prefix)" </dev/null || return 1
}

_portable_tmux() { _with_tmp _do_tmux; }
_do_tmux() {
  local tmp=$1
  fetch_to "$tmp/tmux.appimage" \
    "https://github.com/nelsonenzo/tmux-appimage/releases/download/$TMUX_APPIMAGE_VERSION/tmux.appimage" || return 1
  chmod +x "$tmp/tmux.appimage"
  # Extract rather than run it directly: mounting an AppImage needs FUSE, which a
  # locked-down host is unlikely to have.
  ( cd "$tmp" && ./tmux.appimage --appimage-extract >/dev/null 2>&1 ) || {
    # No FUSE and no extraction support: keep the AppImage itself, it may still run.
    mv "$tmp/tmux.appimage" "$(portable_bin)/tmux"
    return 0
  }
  rm -rf "$(portable_prefix)/tmux-appimage"
  mv "$tmp/squashfs-root" "$(portable_prefix)/tmux-appimage" || return 1
  ln -sfn "$(portable_prefix)/tmux-appimage/AppRun" "$(portable_bin)/tmux"
}

_portable_rust() { _with_tmp _do_rust; }
_do_rust() {
  local tmp=$1
  fetch_to "$tmp/rustup.sh" "https://sh.rustup.rs" || return 1
  # </dev/null for the same reason as zsh-bin: an upstream installer must never be
  # able to block this script on a prompt.
  sh "$tmp/rustup.sh" -y --no-modify-path </dev/null >/dev/null 2>&1 || return 1
}
