#!/usr/bin/env bats

load helper

setup() { setup_common; }
teardown() { teardown_common; }

fonts() {
  bash -c "
    source '$DOTFILES_ROOT/lib/log.sh'
    source '$DOTFILES_ROOT/install/20-fonts.sh'
    $1
  "
}

# Build a fake JetBrainsMono.zip that curl's stub will 'download'.
make_fake_zip() {
  local staging="$TEST_TMP/staging"
  mkdir -p "$staging"
  local i
  for i in 1 2 3; do
    printf 'fake\n' > "$staging/JetBrainsMonoNerdFont-$i.ttf"
  done
  (cd "$staging" && zip -q -r "$TEST_TMP/JetBrainsMono.zip" .)
}

# curl stub that copies the fake zip to whatever -o names.
stub_curl_serving_zip() {
  cat > "$STUB_BIN/curl" <<EOF
#!/usr/bin/env bash
echo "curl \$*" >> "$STUB_LOG"
dest=""
while [ \$# -gt 0 ]; do
  if [ "\$1" = "-o" ]; then dest="\$2"; fi
  shift
done
cp "$TEST_TMP/JetBrainsMono.zip" "\$dest"
EOF
  chmod +x "$STUB_BIN/curl"
}

@test "fonts land in ~/.local/share/fonts on linux" {
  make_fake_zip
  stub_curl_serving_zip
  stub_command fc-cache 0

  run fonts "OS=linux step_fonts"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.local/share/fonts/JetBrainsMonoNerdFont-1.ttf" ]
}

@test "fc-cache runs on linux" {
  make_fake_zip
  stub_curl_serving_zip
  stub_command fc-cache 0
  run fonts "OS=linux step_fonts"
  stub_called "fc-cache"
}

@test "fonts land in ~/Library/Fonts on macos and fc-cache is not run" {
  make_fake_zip
  stub_curl_serving_zip
  stub_command fc-cache 0

  run fonts "OS=macos step_fonts"
  [ "$status" -eq 0 ]
  [ -f "$HOME/Library/Fonts/JetBrainsMonoNerdFont-1.ttf" ]
  ! stub_called "fc-cache"
}

@test "step_fonts warns rather than failing when the download fails" {
  stub_command curl 22
  run fonts "OS=linux step_fonts"
  [ "$status" -eq 2 ]
}

@test "step_fonts is a no-op when the marker file matches the pinned tag" {
  mkdir -p "$HOME/.local/share/fonts"
  printf 'v3.4.0\n' > "$HOME/.local/share/fonts/.jetbrains-nerd-font-version"
  stub_command curl 0
  run fonts "OS=linux step_fonts"
  [ "$status" -eq 0 ]
  ! stub_called "curl"
}

@test "step_fonts under DRY_RUN downloads nothing" {
  stub_command curl 0
  run fonts "DRY_RUN=1 OS=linux step_fonts"
  [ "$status" -eq 0 ]
  ! stub_called "curl"
}
