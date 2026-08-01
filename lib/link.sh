#!/usr/bin/env bash
# The only code that writes into $HOME. Everything is backed up before replacement.

# Move DEST aside into $BACKUP_DIR, preserving its basename.
_displace() {
  local dest=$1
  [ -e "$dest" ] || [ -L "$dest" ] || return 0
  run mkdir -p "$BACKUP_DIR"
  run mv "$dest" "$BACKUP_DIR/$(basename "$dest")"
  # Phrased conditionally: under DRY_RUN nothing actually moved, and claiming
  # otherwise makes the dry-run report untrustworthy.
  if [ "${DRY_RUN:-0}" = "1" ]; then
    log_warn "would move existing $dest to $BACKUP_DIR/"
  else
    log_warn "moved existing $dest to $BACKUP_DIR/"
  fi
}

# For destinations an external tool must own as a regular file. A previous
# install may have linked them, and a link left in place would send that tool's
# writes into this repo — or fail outright, as OMC's coordinator does.
unlink_if_symlink() {
  [ -L "$1" ] || return 0
  _displace "$1"
}

backup_and_link() {
  local src=$1 dest=$2

  if [ ! -e "$src" ]; then
    log_fail "link source missing: $src"
    return 1
  fi

  # Already correct — do nothing, so re-runs stay silent and cheap.
  if [ -L "$dest" ] && [ "$(readlink -f "$dest")" = "$(readlink -f "$src")" ]; then
    log_ok "$dest already linked"
    return 0
  fi

  _displace "$dest"
  run mkdir -p "$(dirname "$dest")"
  run ln -sfn "$src" "$dest" || { log_fail "could not link $dest"; return 1; }
  log_ok "linked $dest -> $src"
}

backup_and_copy() {
  local src=$1 dest=$2

  if [ ! -e "$src" ]; then
    log_fail "copy source missing: $src"
    return 1
  fi

  _displace "$dest"
  run mkdir -p "$(dirname "$dest")"
  if [ -d "$src" ]; then
    run cp -R "$src" "$dest" || { log_fail "could not copy $dest"; return 1; }
  else
    run cp "$src" "$dest" || { log_fail "could not copy $dest"; return 1; }
  fi
  log_ok "copied $dest"
}
