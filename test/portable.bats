#!/usr/bin/env bats
#
# Provisioning runtime tools without sudo: fetch prebuilt binaries into a
# user-writable prefix instead of requiring a package manager.

load helper

setup() {
  setup_common
  export PORTABLE_PREFIX="$TEST_TMP/prefix"
  export ARCH=x86_64
  export OS=linux
}
teardown() { teardown_common; }

portable() {
  bash -c "
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/portable.sh'
    export PORTABLE_PREFIX='$PORTABLE_PREFIX'
    $1
  "
}

# curl stub that materialises whatever file is requested via -o
stub_curl_writes() {   # stub_curl_writes <payload-generator-shell>
  cat > "$STUB_BIN/curl" <<EOF
#!/usr/bin/env bash
echo "curl \$*" >> "$STUB_LOG"
dest=""
while [ \$# -gt 0 ]; do
  if [ "\$1" = "-o" ]; then dest="\$2"; fi
  shift
done
[ -n "\$dest" ] || exit 0
$1
exit 0
EOF
  chmod +x "$STUB_BIN/curl"
}

# --- prefix -----------------------------------------------------------------

@test "portable_bin defaults under HOME when PORTABLE_PREFIX is unset" {
  run bash -c "
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/portable.sh'
    unset PORTABLE_PREFIX
    portable_bin
  "
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.local/bin" ]
}

@test "portable_bin honours PORTABLE_PREFIX" {
  run portable "portable_bin"
  [ "$output" = "$PORTABLE_PREFIX/bin" ]
}

# --- sudo detection ---------------------------------------------------------

@test "have_sudo is false when sudo is absent" {
  run bash -c "PATH='$STUB_BIN'; source '$DOTFILES_ROOT/lib/log.sh'; source '$DOTFILES_ROOT/lib/portable.sh'; have_sudo"
  [ "$status" -ne 0 ]
}

@test "have_sudo is false when sudo exists but needs a password" {
  stub_command sudo 1
  run portable "have_sudo"
  [ "$status" -ne 0 ]
}

@test "have_sudo is true when passwordless sudo works" {
  stub_command sudo 0
  run portable "have_sudo"
  [ "$status" -eq 0 ]
}

# --- fetch ------------------------------------------------------------------

@test "fetch_to uses curl when available" {
  stub_curl_writes 'printf payload > "$dest"'
  run portable "fetch_to '$TEST_TMP/out' https://example.invalid/x"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMP/out")" = "payload" ]
  stub_called "curl"
}

@test "fetch_to falls back to wget when curl is absent" {
  cat > "$STUB_BIN/wget" <<EOF
#!/usr/bin/env bash
echo "wget \$*" >> "$STUB_LOG"
dest=""
while [ \$# -gt 0 ]; do
  if [ "\$1" = "-O" ]; then dest="\$2"; fi
  shift
done
printf wgot > "\$dest"
EOF
  chmod +x "$STUB_BIN/wget"
  # a PATH without the real curl, but still holding the utilities a stub needs to run
  run bash -c "
    PATH='$(sandbox_path)'
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/portable.sh'
    fetch_to '$TEST_TMP/out' https://example.invalid/x
  "
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMP/out")" = "wgot" ]
}

@test "fetch_to fails clearly when neither curl nor wget exists" {
  run bash -c "
    PATH='$(sandbox_path)'
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/portable.sh'
    fetch_to '$TEST_TMP/out' https://example.invalid/x 2>&1
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"curl"* ]]
  [[ "$output" == *"wget"* ]]
}

# --- support matrix ---------------------------------------------------------

@test "portable_supported knows the tools it can fetch" {
  for t in nvim node jq zsh rust; do
    run portable "OS=linux portable_supported $t"
    [ "$status" -eq 0 ]
  done
}

@test "tmux is fetchable on linux but not on macos" {
  run portable "OS=linux portable_supported tmux"
  [ "$status" -eq 0 ]
  run portable "OS=macos portable_supported tmux"
  [ "$status" -ne 0 ]
}

@test "git is not claimed as fetchable" {
  run portable "portable_supported git"
  [ "$status" -ne 0 ]
}

@test "portable_install rejects an unknown tool with a clear message" {
  run portable "portable_install nosuchtool 2>&1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"nosuchtool"* ]]
}

# --- installing -------------------------------------------------------------

@test "portable_install jq places an executable binary on the prefix bin" {
  stub_curl_writes 'printf "#!/bin/sh\necho jq-1.7.1\n" > "$dest"'
  run portable "portable_install jq"
  [ "$status" -eq 0 ]
  [ -x "$PORTABLE_PREFIX/bin/jq" ]
  [ "$("$PORTABLE_PREFIX/bin/jq")" = "jq-1.7.1" ]
}

@test "portable_install nvim extracts the tarball and exposes the binary" {
  # build a tarball shaped like the real nvim release
  local stage="$TEST_TMP/stage/nvim-linux-x86_64"
  mkdir -p "$stage/bin"
  printf '#!/bin/sh\necho NVIM 0.12.4\n' > "$stage/bin/nvim"
  chmod +x "$stage/bin/nvim"
  ( cd "$TEST_TMP/stage" && tar czf "$TEST_TMP/nvim.tar.gz" nvim-linux-x86_64 )
  stub_curl_writes "cp '$TEST_TMP/nvim.tar.gz' \"\$dest\""

  run portable "portable_install nvim"
  [ "$status" -eq 0 ]
  [ -x "$PORTABLE_PREFIX/bin/nvim" ]
  [ "$("$PORTABLE_PREFIX/bin/nvim")" = "NVIM 0.12.4" ]
}

@test "portable_install is a no-op when the tool is already on the prefix" {
  mkdir -p "$PORTABLE_PREFIX/bin"
  printf '#!/bin/sh\necho existing\n' > "$PORTABLE_PREFIX/bin/jq"
  chmod +x "$PORTABLE_PREFIX/bin/jq"
  stub_command curl 0
  run portable "portable_install jq"
  [ "$status" -eq 0 ]
  ! stub_called "curl"
  [ "$("$PORTABLE_PREFIX/bin/jq")" = "existing" ]
}

@test "portable_install under DRY_RUN downloads nothing" {
  stub_command curl 0
  run portable "DRY_RUN=1 portable_install jq"
  [ "$status" -eq 0 ]
  ! stub_called "curl"
  [ ! -e "$PORTABLE_PREFIX/bin/jq" ]
}

@test "a failed download does not leave a half-written binary" {
  cat > "$STUB_BIN/curl" <<EOF
#!/usr/bin/env bash
echo "curl \$*" >> "$STUB_LOG"
exit 22
EOF
  chmod +x "$STUB_BIN/curl"
  run portable "portable_install jq"
  [ "$status" -ne 0 ]
  [ ! -e "$PORTABLE_PREFIX/bin/jq" ]
}

@test "portable_install rust delegates to rustup and does not need a prefix bin" {
  stub_curl_writes 'printf "#!/bin/sh\nexit 0\n" > "$dest"'
  stub_command sh 0
  # This machine has a real cargo on PATH, which would short-circuit the install.
  # Narrow PATH so the "not yet installed" branch is the one under test.
  run bash -c "
    PATH='$STUB_BIN:/usr/bin:/bin'
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/lib/portable.sh'
    export PORTABLE_PREFIX='$PORTABLE_PREFIX'
    portable_install rust
  "
  [ "$status" -eq 0 ]
  stub_called "curl"
}

@test "portable_install rust is a no-op when cargo is already available" {
  stub_command cargo 0
  stub_command curl 0
  run portable "portable_install rust"
  [ "$status" -eq 0 ]
  ! stub_called "curl"
}

# --- guards against hanging on an upstream prompt ----------------------------

@test "zsh install passes -e no so it cannot block on the /etc/shells prompt" {
  # The installer defaults to -e ask, which waits on stdin forever in an
  # unattended run. It also needs root to write /etc/shells.
  grep -q -- '-e no' "$DOTFILES_ROOT/lib/portable.sh"
  run bash -c "grep -A2 'zsh-bin/master/install' '$DOTFILES_ROOT/lib/portable.sh' | grep -- '-e no'"
  [ "$status" -eq 0 ]
}

@test "zsh install verifies the download integrity" {
  run bash -c "grep -A2 'zsh-bin/master/install' '$DOTFILES_ROOT/lib/portable.sh' | grep -- '-a sha256'"
  [ "$status" -eq 0 ]
}

@test "every upstream installer invocation is protected from stdin prompts" {
  # any `sh <downloaded script>` must redirect stdin, or an added prompt hangs us
  run bash -c "grep -nE '^\\s*sh \"\\\$tmp' '$DOTFILES_ROOT/lib/portable.sh' | grep -v '</dev/null'"
  [ "$status" -ne 0 ]
}
