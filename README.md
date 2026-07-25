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

## What is shared and what is per-host

`~/.zshrc` is portable and tracked here. Everything machine-specific — EDA tool
paths, license servers, corporate CA certificates, WSL shortcuts, and the
`claude --dangerously-skip-permissions` alias — lives in `~/.zshrc.local`, which
is seeded from `home/.zshrc.local.example` and never tracked.

The same split applies to Claude Code: `settings.json` is shared,
`settings.local.json` is per-host. `skipDangerousModePermissionPrompt` is
deliberately *not* in the shared settings, so a fresh machine starts with
permission prompts enabled.

## What gets installed

| Component | Detail |
|---|---|
| Dependencies | Homebrew on both platforms: zsh, tmux, git, neovim, node |
| Fonts | JetBrainsMono Nerd Font v3.4.0, all variants |
| zsh | oh-my-zsh, `robbyrussell`, `plugins=(git)` |
| tmux | oh-my-tmux pinned to `af33f07`, tpm, tmux-agent-indicator, extrakto |
| Neovim | NvChad v2.5, plugins restored from `lazy-lock.json` |
| Claude Code | CLI, `settings.json`, `CLAUDE.md`, OMC HUD, 61 skills (59 linked) |

Backups of anything displaced go to `~/.dotfiles-backup/<timestamp>/`. Nothing is
ever deleted or overwritten in place.

## Layout

| Path | Purpose |
|---|---|
| `install.sh` | Entrypoint: flags, step ordering, dispatch, summary |
| `verify.sh` | Post-install assertions, runnable standalone |
| `lib/` | `log.sh` (output + dry-run), `os.sh` (OS/brew), `link.sh` (backup+symlink) |
| `install/` | One file per step, `00-preflight` through `70-skills` |
| `home/` | zsh config plus the per-host example |
| `config/` | tmux and Neovim config |
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

## Never push

This repo has no remote by design.
