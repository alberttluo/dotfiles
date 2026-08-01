#!/usr/bin/env bats

load helper

setup() {
  setup_common
  export BACKUP_DIR="$TEST_TMP/backup"
  mkdir -p "$BACKUP_DIR"
}
teardown() { teardown_common; }

nvim_step() {
  bash -c "
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/link.sh'
    export DOTFILES_ROOT='$DOTFILES_ROOT' BACKUP_DIR='$BACKUP_DIR'
    source '$DOTFILES_ROOT/install/50-nvim.sh'
    $1
  "
}

@test "the vendored nvim config carries the lazy lockfile" {
  [ -f "$DOTFILES_ROOT/config/nvim/lazy-lock.json" ]
  run jq -e 'type == "object"' "$DOTFILES_ROOT/config/nvim/lazy-lock.json"
  [ "$status" -eq 0 ]
}

# nvim-treesitter's master branch was archived at v0.10.0 and does not support
# Neovim 0.11+; NvChad also calls require("nvim-treesitter").install(), which
# exists only on main. Nothing else pins the branch, so a lazy update that
# resolves the repo default is enough to strand the checkout on master and throw
# on every markdown buffer.
@test "nvim-treesitter is pinned to the main branch in both spec and lockfile" {
  grep -q 'branch = "main"' "$DOTFILES_ROOT/config/nvim/lua/plugins/init.lua"
  run jq -r '."nvim-treesitter".branch' "$DOTFILES_ROOT/config/nvim/lazy-lock.json"
  [ "$output" = "main" ]
}

@test "the vendored nvim config carries the custom tabline" {
  [ -f "$DOTFILES_ROOT/config/nvim/lua/albert/tabline.lua" ]
}

@test "the vendored nvim config has no machine-specific paths" {
  ! grep -rqE '/mnt/c|/home/alluo' "$DOTFILES_ROOT/config/nvim"
}

@test "the vendored nvim config carries no operational state" {
  # Asserts nothing is *tracked*, not that nothing exists on disk: any tool run
  # with a cwd inside this directory can drop state here at any moment (OMC writes
  # .omc/state relative to cwd). Presence is harmless while .gitignore holds; a
  # tracked file is the actual defect.
  run bash -c "cd '$DOTFILES_ROOT' && git ls-files config/nvim | grep -E '(^|/)\.(omc|git)/'"
  [ "$status" -ne 0 ]
  # a nested git repo would break the packaging outright, so that must not exist
  [ ! -d "$DOTFILES_ROOT/config/nvim/.git" ]
  # and .omc must stay ignored, or the above could start passing silently
  run bash -c "cd '$DOTFILES_ROOT' && git check-ignore -q config/nvim/.omc/"
  [ "$status" -eq 0 ]
}

@test "step_nvim links ~/.config/nvim to the repo copy" {
  stub_command nvim 0
  run nvim_step "step_nvim"
  [ "$status" -eq 0 ]
  [ -L "$HOME/.config/nvim" ]
  [ -f "$HOME/.config/nvim/init.lua" ]
}

@test "step_nvim restores plugins from the lockfile rather than syncing" {
  stub_command nvim 0
  run nvim_step "step_nvim"
  stub_called "Lazy! restore"
  ! stub_called "Lazy! sync"
}

@test "step_nvim warns rather than failing when headless nvim fails" {
  stub_command nvim 1
  run nvim_step "step_nvim"
  [ "$status" -eq 2 ]
  [ -L "$HOME/.config/nvim" ]
}

@test "step_nvim under DRY_RUN does not invoke nvim" {
  stub_command nvim 0
  run nvim_step "DRY_RUN=1 step_nvim"
  [ "$status" -eq 0 ]
  ! stub_called "Lazy!"
}
