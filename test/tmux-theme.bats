#!/usr/bin/env bats
#
# Guards the regression that a syntax-only check cannot catch: oh-my-tmux loads
# its variables but never applies the theme, leaving a stock-looking status bar.

load helper

setup() { setup_common; }
teardown() { teardown_common; }

# Stub tmux so `show -gv status-style` / `status-left` return chosen values and a
# server always appears to exist (so the predicate does not create one).
stub_tmux_reporting() {  # stub_tmux_reporting <style> <left>
  cat > "$STUB_BIN/tmux" <<EOF
#!/usr/bin/env bash
echo "tmux \$*" >> "$STUB_LOG"
case "\$*" in
  "ls")                    exit 0 ;;
  *"show -gv status-style") printf '%s\n' '$1' ;;
  *"show -gv status-left")  printf '%s\n' '$2' ;;
  *)                        exit 0 ;;
esac
EOF
  chmod +x "$STUB_BIN/tmux"
}

themed() {
  bash -c "
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/verify.sh' --source-only
    _tmux_themed
  "
}

@test "_tmux_themed fails when the status bar shows stock tmux values" {
  stub_tmux_reporting "bg=green,fg=black" "[#{session_name}]"
  run themed
  [ "$status" -ne 0 ]
}

@test "_tmux_themed passes when the oh-my-tmux theme is applied" {
  stub_tmux_reporting "fg=#a6adc8,bg=#1e1e2e,none" "#[fg=#1e1e2e,bg=#cba6f7,bold] 🦥 #S "
  run themed
  [ "$status" -eq 0 ]
}

@test "_tmux_themed fails when only status-left is stock" {
  stub_tmux_reporting "fg=#a6adc8,bg=#1e1e2e,none" "[#{session_name}]"
  run themed
  [ "$status" -ne 0 ]
}

@test "_tmux_themed fails when tmux reports nothing" {
  stub_tmux_reporting "" ""
  run themed
  [ "$status" -ne 0 ]
}

@test "_tmux_themed queries the default socket, never a -L socket" {
  stub_tmux_reporting "fg=#a6adc8,bg=#1e1e2e,none" "#[fg=#1e1e2e] 🦥 #S "
  run themed
  # oh-my-tmux misdetects TMUX_PROGRAM on a named socket, so -L must not be used
  ! stub_called "-L"
}

@test "verify.sh runs the theme check" {
  grep -q '_tmux_themed' "$DOTFILES_ROOT/verify.sh"
  grep -q 'check "oh-my-tmux theme actually applied"' "$DOTFILES_ROOT/verify.sh"
}
