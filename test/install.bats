#!/usr/bin/env bats

load helper

setup() {
  setup_common
  # Sandbox copy of the repo so stub steps can be swapped in freely.
  export REPO="$TEST_TMP/repo"
  mkdir -p "$REPO"
  cp -R "$DOTFILES_ROOT/lib" "$DOTFILES_ROOT/install.sh" "$REPO/"
  mkdir -p "$REPO/install"
}
teardown() { teardown_common; }

write_step() {  # write_step <file> <func> <return_code>
  cat > "$REPO/install/$1" <<EOF
#!/usr/bin/env bash
$2() { echo "ran $2" >> "$STUB_LOG"; return $3; }
EOF
}

@test "--help exits 0 and lists the flags" {
  run bash "$REPO/install.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--dry-run"* ]]
  [[ "$output" == *"--only"* ]]
  [[ "$output" == *"--skip-fonts"* ]]
  [[ "$output" == *"--portable"* ]]
  [[ "$output" == *"--data-root"* ]]
}

@test "--data-root points the relocatable tools at the given root" {
  cat > "$REPO/install/00-preflight.sh" <<EOF
#!/usr/bin/env bash
step_preflight() {
  echo "prefix=\$PORTABLE_PREFIX cargo=\$CARGO_HOME claude=\$CLAUDE_CONFIG_DIR" >> "$STUB_LOG"
  return 0
}
EOF
  run bash "$REPO/install.sh" --data-root "$TEST_TMP/ece"
  stub_called "prefix=$TEST_TMP/ece"
  stub_called "cargo=$TEST_TMP/ece/cargo"
  stub_called "claude=$TEST_TMP/ece/claude"
}

@test "--data-root requires a directory argument" {
  run bash "$REPO/install.sh" --data-root
  [ "$status" -ne 0 ]
}

@test "without --data-root nothing is relocated" {
  cat > "$REPO/install/00-preflight.sh" <<EOF
#!/usr/bin/env bash
step_preflight() { echo "prefix=\${PORTABLE_PREFIX:-unset}" >> "$STUB_LOG"; return 0; }
EOF
  run bash "$REPO/install.sh"
  stub_called "prefix=unset"
}

@test "--portable exports PORTABLE_ONLY=1 to steps" {
  cat > "$REPO/install/00-preflight.sh" <<EOF
#!/usr/bin/env bash
step_preflight() { echo "portable=\${PORTABLE_ONLY:-unset}" >> "$STUB_LOG"; return 0; }
EOF
  run bash "$REPO/install.sh" --portable
  stub_called "portable=1"
}

@test "the portable provisioning library is available to steps" {
  cat > "$REPO/install/00-preflight.sh" <<EOF
#!/usr/bin/env bash
step_preflight() { command -v portable_install >/dev/null && echo "have_portable" >> "$STUB_LOG"; return 0; }
EOF
  run bash "$REPO/install.sh"
  stub_called "have_portable"
}

@test "rejects an unknown flag" {
  run bash "$REPO/install.sh" --wat
  [ "$status" -ne 0 ]
  [[ "$output" == *"--wat"* ]]
}

@test "runs all steps in order" {
  write_step 00-preflight.sh step_preflight 0
  write_step 10-packages.sh step_packages 0
  run bash "$REPO/install.sh"
  [ "$status" -eq 0 ]
  stub_called "ran step_preflight"
  stub_called "ran step_packages"
}

@test "--only runs just the named step" {
  write_step 00-preflight.sh step_preflight 0
  write_step 10-packages.sh step_packages 0
  run bash "$REPO/install.sh" --only 10-packages
  [ "$status" -eq 0 ]
  ! stub_called "ran step_preflight"
  stub_called "ran step_packages"
}

@test "--only with an unknown step id fails" {
  write_step 00-preflight.sh step_preflight 0
  run bash "$REPO/install.sh" --only 99-nope
  [ "$status" -ne 0 ]
}

@test "a hard failure (return 1) aborts before later steps" {
  write_step 00-preflight.sh step_preflight 1
  write_step 10-packages.sh step_packages 0
  run bash "$REPO/install.sh"
  [ "$status" -eq 1 ]
  ! stub_called "ran step_packages"
}

@test "a warn (return 2) continues to later steps and still exits 0" {
  write_step 00-preflight.sh step_preflight 2
  write_step 10-packages.sh step_packages 0
  run bash "$REPO/install.sh"
  [ "$status" -eq 0 ]
  stub_called "ran step_packages"
}

@test "--skip-fonts skips the fonts step" {
  write_step 20-fonts.sh step_fonts 0
  run bash "$REPO/install.sh" --skip-fonts
  [ "$status" -eq 0 ]
  ! stub_called "ran step_fonts"
}

@test "--dry-run exports DRY_RUN=1 to steps" {
  cat > "$REPO/install/00-preflight.sh" <<'EOF'
#!/usr/bin/env bash
step_preflight() { echo "dry=${DRY_RUN:-0}" >> "$STUB_LOG"; return 0; }
EOF
  run bash "$REPO/install.sh" --dry-run
  [ "$status" -eq 0 ]
  stub_called "dry=1"
}

@test "summary lists the manual follow-ups" {
  write_step 00-preflight.sh step_preflight 0
  run bash "$REPO/install.sh"
  [[ "$output" == *"claude"* ]]
  [[ "$output" == *".zshrc.local"* ]]
}
