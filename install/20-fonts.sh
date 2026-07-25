#!/usr/bin/env bash
# Install JetBrainsMono Nerd Font from the pinned upstream release.
#
# A release zip is used on both operating systems rather than a Homebrew cask,
# because casks are macOS-only and one code path is less to keep in sync.

NERD_FONTS_TAG="${NERD_FONTS_TAG:-v3.4.0}"
NERD_FONT_ASSET="JetBrainsMono.zip"

_font_dir() {
  if [ "${OS:-linux}" = "macos" ]; then
    printf '%s\n' "$HOME/Library/Fonts"
  else
    printf '%s\n' "$HOME/.local/share/fonts"
  fi
}

step_fonts() {
  local dir marker url tmp count
  dir="$(_font_dir)"
  marker="$dir/.jetbrains-nerd-font-version"

  if [ -f "$marker" ] && [ "$(cat "$marker")" = "$NERD_FONTS_TAG" ]; then
    log_ok "JetBrainsMono Nerd Font $NERD_FONTS_TAG already installed"
    return 0
  fi

  if [ "${DRY_RUN:-0}" = "1" ]; then
    log_dry "download $NERD_FONT_ASSET $NERD_FONTS_TAG into $dir"
    return 0
  fi

  url="https://github.com/ryanoasis/nerd-fonts/releases/download/$NERD_FONTS_TAG/$NERD_FONT_ASSET"
  tmp="$(mktemp -d)"

  if ! curl -fsSL -o "$tmp/$NERD_FONT_ASSET" "$url"; then
    rm -rf "$tmp"
    log_warn "font download failed ($url) — skipping fonts"
    return 2
  fi

  mkdir -p "$dir"
  if ! unzip -qo "$tmp/$NERD_FONT_ASSET" -d "$dir" 'JetBrainsMono*'; then
    rm -rf "$tmp"
    log_warn "font archive could not be extracted — skipping fonts"
    return 2
  fi
  rm -rf "$tmp"

  # fontconfig is Linux-only; macOS picks up ~/Library/Fonts with no cache step.
  if [ "${OS:-linux}" = "linux" ]; then
    if command -v fc-cache >/dev/null 2>&1; then
      fc-cache -f "$dir" >/dev/null 2>&1 || log_warn "fc-cache failed"
    else
      log_warn "fc-cache not found — fonts may not be visible until you log out"
    fi
  fi

  printf '%s\n' "$NERD_FONTS_TAG" > "$marker"
  count="$(find "$dir" -name 'JetBrainsMono*' -type f | wc -l | tr -d ' ')"
  log_ok "installed JetBrainsMono Nerd Font $NERD_FONTS_TAG ($count files)"
}
