# dotfiles

Portable tmux + zsh + Neovim + Claude Code setup for macOS and Red Hat Linux.

## Install

```bash
git clone <this repo> ~/dotfiles
cd ~/dotfiles
./install.sh
```

Then, because neither can be automated:

1. Run `claude` and log in. Credentials are never packaged.
2. Fill in `~/.zshrc.local` with this machine's paths, license servers, and aliases.

Preview without changing anything: `./install.sh --dry-run`.
Re-run one step: `./install.sh --only 40-tmux`.
Check an existing install: `./verify.sh`.

### No sudo

Homebrew cannot be installed without root, so on a locked-down host use:

```
./install.sh --portable
```

This skips Homebrew entirely and downloads pinned prebuilt binaries into
`~/.local` instead — zsh, tmux, Neovim, node, jq and rust. A plain `./install.sh`
does the same automatically for anything Homebrew could not provide, so the flag
only matters when you want to bypass a working Homebrew.

Two things are never fetched this way: `git`, which you already need to clone
this repo, and tmux on macOS, which publishes no static build. Everything that
needs no privileges at all — zsh, tmux, Neovim and Claude Code config — installs
regardless.

## What is shared and what is per-host

`~/.zshrc` is portable and tracked here. Everything machine-specific — EDA tool
paths, license servers, corporate CA certificates, WSL shortcuts, and the
`claude --dangerously-skip-permissions` alias — lives in `~/.zshrc.local`, which
is seeded from `home/.zshrc.local.example` and never tracked.

The same split applies to Claude Code: `settings.json` is shared,
`settings.local.json` is per-host. `skipDangerousModePermissionPrompt` is
deliberately *not* in the shared settings, so a fresh machine starts with
permission prompts enabled.

### Linked vs copied

| Installed by | Files | Why |
|---|---|---|
| symlink | `.zshrc`, `.zshenv`, `tmux.conf.local`, `config/nvim`, `CLAUDE.md` | Author-edited only. Edits in the repo take effect immediately. |
| copy | `claude/settings.json`, `claude/hud/` | **The application writes to these.** Claude Code persists theme, model, and permission state into `settings.json`; the HUD writes per-session cache into `hud/cache/`. Symlinking them makes the repo the write target for runtime state — which silently re-added a per-host permission bypass to this repo once. |

Changing a copied file in the repo needs `./install.sh --only 60-claude` to take
effect. That is the deliberate cost of keeping runtime writes out of git.

## What gets installed

| Component | Detail |
|---|---|
| Dependencies | Homebrew on both platforms: zsh, tmux, git, neovim, node, jq, rust; pinned prebuilt downloads into `~/.local` when Homebrew is unavailable |
| Fonts | JetBrainsMono Nerd Font v3.4.0, all variants |
| zsh | oh-my-zsh, `robbyrussell`, `plugins=(git)` |
| tmux | oh-my-tmux pinned to `af33f07`, tpm, tmux-agent-indicator, extrakto |
| Neovim | NvChad v2.5, plugins restored from `lazy-lock.json` |
| Claude Code | CLI, `settings.json`, `CLAUDE.md`, OMC HUD, 61 skills (59 linked) |
| context-manager | `config.toml`, plus the daemon itself: cloned and built from its own repo (Linux only) |

Backups of anything displaced go to `~/.dotfiles-backup/<timestamp>/`. Nothing is
ever deleted or overwritten in place.

### A note on tmux config paths

oh-my-tmux resolves its config as the first existing of `~/.tmux.conf`,
`$XDG_CONFIG_HOME/tmux/tmux.conf`, `~/.config/tmux/tmux.conf`, then derives
`TMUX_CONF_LOCAL` as `"$TMUX_CONF.local"`. Two consequences the installer handles
explicitly, because getting either wrong yields a stock-looking tmux while every
other component installs perfectly:

- A leftover `~/.tmux.conf` outranks the XDG path, so it is moved to the backup
  directory along with any `~/.tmux.conf.local`.
- `XDG_CONFIG_HOME` is honoured rather than assuming `~/.config`.

### A note on context-manager

`context-manager` is a user-level daemon that hands a Claude Code session off to
a fresh one before it exhausts its context window: past a threshold it asks the
live session to write a handoff document, then replaces it in the same tmux pane
with a new session seeded from that document.

This is the one component built from source. The `context-managerd` and `cm-hook`
binaries are Rust and live in their own repo, so the step clones (or
fast-forwards) that repo into `~/src/context-manager` and delegates to its
`deploy/install.sh`, which builds, installs the binaries, and enables the
systemd user service. Delegating rather than reimplementing keeps the two from
drifting. Override the source location with `CM_SRC_DIR` and the origin with
`CM_REPO_URL`.

That makes `cargo` a build dependency, so the Brewfile now carries `rust` (a
rustup toolchain already on the machine is preferred and used instead). A missing
toolchain or an unreachable remote is reported as a follow-up, not a hard
failure: the config is still seeded and the rest of the install completes.

The step is **Linux-only** — the daemon runs as a `systemd --user` service, which
macOS has no equivalent of — and is a clean no-op on macOS. The
`SessionStart`/`SessionEnd` hooks the daemon needs ship in
`claude/settings.json`, so a machine without the binaries is simply unmanaged
rather than broken.

`config.toml` is **seeded, not overwritten**: `ignore_cwds` holds machine-specific
paths and the thresholds are tuned against a live machine, so the step never
clobbers an existing file and instead warns when it has drifted from the tracked
copy. `ignore_cwds` matching is a plain substring test, so one ancestor path
excludes every project beneath it.

## Layout

| Path | Purpose |
|---|---|
| `install.sh` | Entrypoint: flags, step ordering, dispatch, summary |
| `verify.sh` | Post-install assertions, runnable standalone |
| `lib/` | `log.sh` (output + dry-run), `os.sh` (OS/brew), `link.sh` (backup+symlink), `portable.sh` (sudo-less downloads) |
| `install/` | One file per step, `00-preflight` through `80-context-manager` |
| `home/` | zsh config plus the per-host example |
| `config/` | tmux, Neovim, and context-manager config |
| `claude/` | Claude Code settings, CLAUDE.md, HUD |
| `agents/` | Vendored skills tree, lock file, link manifest |
| `test/` | bats suites, Rocky 9 integration test |
| `docs/superpowers/` | Design spec and implementation plan |

Each step function returns 0 (ok), 1 (hard fail, aborts the run), or 2 (warn and
continue). Fonts, tmux plugin installation, and Neovim plugin restore are all
warn-class: they never block an install.

## Tests

```bash
brew bundle --file=Brewfile.dev   # bats-core, shellcheck, shfmt
bats test/                        # unit tests
shellcheck -x install.sh verify.sh lib/*.sh install/*.sh
./test/run-container-test.sh      # full install on rockylinux:9 (needs docker)
```

**macOS is not covered by an automated test** — no Mac was available to the
author. macOS support rests on shellcheck and review of the three
platform-divergent branches: the Homebrew prefix (`/opt/homebrew` vs
`/usr/local`), the font destination (`~/Library/Fonts`), and whether `fc-cache`
runs. Use `--dry-run` on a Mac first.

## Remote

`origin` is `git@github.com:alberttluo/dotfiles.git`.

Note that `home/.zshrc.local.example` and the design docs reference internal
infrastructure — a license server host, a project codename, and local Windows
paths. Keep this repository private, or scrub those before making it public.
