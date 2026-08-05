# dotfiles

Portable tmux + zsh + Neovim + Claude Code setup for macOS and Red Hat Linux.

## Install

```bash
git clone --recursive <this repo> ~/dotfiles
cd ~/dotfiles
./install.sh
```

`--recursive` brings in `vendor/context-manager`. Forgetting it is not fatal —
the install checks the submodule out itself — but it costs a network round trip
mid-install.

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

### When $HOME is too small

Some hosts give you a small, separately-quota'd home volume and a larger one
elsewhere — CMU's AFS andrew space next to ece space is the case this was built
for. A normal install puts several GB in `$HOME`; almost none of it is
configuration.

```
./install.sh --portable --data-root /afs/ece.cmu.edu/usr/<andrewid>/dotfiles-data
```

Config stays in `$HOME`, because zsh reads `~/.zshenv` before anything else can
run. Everything else moves:

| Under the data root | What it holds |
|---|---|
| `bin/`, `nvim/`, `node/` | prebuilt binaries |
| `cargo/`, `rustup/` | Rust toolchain |
| `share/`, `state/`, `cache/` | `XDG_*`: fonts, nvim plugins, tmux trees |
| `oh-my-zsh/`, `nvm/` | shell and node frameworks |
| `claude/` | Claude Code config **and** its transcripts, which grow without bound |
| `agents/` | the 61-skill tree |
| `cargo-target/` | `CARGO_TARGET_DIR`: the daemon's Rust build output |

What stays in `$HOME`: `.zshrc`, `.zshenv`, `.zshrc.local`, `.config/nvim` (a
symlink into this repo), `.config/context-manager/config.toml`, and
`.dotfiles-env`.

Relocation is done with the environment variables each tool already supports
(`XDG_DATA_HOME`, `CARGO_HOME`, `ZSH`, `CLAUDE_CONFIG_DIR`, …), not symlinks: a
link into a volume that is not mounted, or for which you hold no AFS token,
fails far less legibly than an unset variable.

The installer writes those variables to `~/.dotfiles-env`, which `~/.zshenv`
sources, so your shells resolve the same locations afterwards — and re-running
`./install.sh` from such a shell keeps the same root without repeating the flag.
`verify.sh` reads that file too.

On AFS specifically: `chsh` is usually unavailable, so take the `~/.bashrc`
fallback the installer prints. If the data root cannot be created, check `fs
listacl` on its parent and that you still hold a token (`klist`) — neither looks
like a permission error to `mkdir`. Fonts installed on a remote VM do nothing
for a terminal running on your laptop; install those locally.

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
| symlink | `.zshrc`, `.zshenv`, `tmux.conf.local`, `config/nvim`, `CLAUDE-user.md` | Author-edited only. Edits in the repo take effect immediately. |
| copy | `claude/settings.json`, `claude/hud/` | **The application writes to these.** Claude Code persists theme, model, and permission state into `settings.json`; the HUD writes per-session cache into `hud/cache/`. Symlinking them makes the repo the write target for runtime state — which silently re-added a per-host permission bypass to this repo once. |
| generated | `~/.claude/CLAUDE.md` | oh-my-claudecode rewrites it on every release, and its setup coordinator **refuses to write through a symlink**. Not tracked at all. |

Changing a copied file in the repo needs `./install.sh --only 60-claude` to take
effect. That is the deliberate cost of keeping runtime writes out of git.

### CLAUDE.md is split in two

`~/.claude/CLAUDE.md` is owned by oh-my-claudecode, not by this repo. It holds
OMC's generated block plus one line — `@CLAUDE-user.md` — importing the personal
instructions, which *are* tracked here and symlinked into place. OMC regenerates
its own block and preserves everything below it, so `/oh-my-claudecode:setup`
updates itself with no merging by hand and no risk to the tracked file.

`60-claude` also runs OMC's `setup-claude-md.sh` itself, so a plain
`./install.sh` refreshes the generated block too. On a brand-new machine the OMC
plugin is not cached until Claude Code first launches; the step warns and leaves
the import in place, and the next `/oh-my-claudecode:setup` fills in the rest.

## What gets installed

| Component | Detail |
|---|---|
| Dependencies | Homebrew on both platforms: zsh, tmux, git, neovim, node, jq, rust; pinned prebuilt downloads into `~/.local` when Homebrew is unavailable |
| Fonts | JetBrainsMono Nerd Font v3.4.0, all variants |
| zsh | oh-my-zsh, `robbyrussell`, `plugins=(git)` |
| tmux | oh-my-tmux pinned to `af33f07`, tpm, tmux-agent-indicator, extrakto |
| Neovim | NvChad v2.5, plugins restored from `lazy-lock.json` |
| Claude Code | CLI, `settings.json`, `CLAUDE-user.md`, OMC HUD, 61 skills (59 linked) |
| context-manager | `config.toml`, plus the daemon itself: built from the `vendor/context-manager` submodule (Linux only) |

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
binaries are Rust and live in their own repo, vendored here as the submodule
`vendor/context-manager`. The step delegates to its `deploy/install.sh`, which
builds, installs the binaries, and enables the systemd user service. Delegating
rather than reimplementing keeps the two from drifting.

A submodule rather than a clone into `~/src` so that the daemon a given dotfiles
commit installs is pinned by that commit. Installing never moves the pin;
updating the daemon is deliberate:

```bash
git submodule update --remote vendor/context-manager
git commit -m 'chore: bump context-manager' vendor/context-manager
```

The source is small enough to sit in `$HOME`, but its build output is not, so
`--data-root` sets `CARGO_TARGET_DIR` and cargo writes there instead of into
`vendor/context-manager/target`.

That makes `cargo` a build dependency, so the Brewfile now carries `rust` (a
rustup toolchain already on the machine is preferred and used instead). A missing
toolchain or a submodule that cannot be checked out is reported as a follow-up,
not a hard failure: the config is still seeded and the rest of the install
completes.

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
| `lib/` | `log.sh` (output + dry-run), `os.sh` (OS/brew), `link.sh` (backup+symlink), `portable.sh` (sudo-less downloads), `data-root.sh` (relocation off `$HOME`) |
| `install/` | One file per step, `00-preflight` through `80-context-manager` |
| `home/` | zsh config plus the per-host example |
| `config/` | tmux, Neovim, and context-manager config |
| `claude/` | Claude Code settings, personal CLAUDE-user.md, HUD |
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

The suite is host-independent: every test that exercises a platform-divergent
branch pins `uname` rather than inheriting the developer's kernel. That matters
more than it sounds — `80-context-manager` returns early on macOS, so its ten
Linux-path tests passed vacuously on a Mac until they were pinned.

`bats test/` and `./verify.sh` both pass on macOS 26 (Apple Silicon) against a
real install. The platform-divergent branches are the Homebrew prefix (`/opt/homebrew`
vs `/usr/local`), the font destination (`~/Library/Fonts`), whether `fc-cache`
runs, and whether context-manager installs at all.

## Remote

`origin` is `git@github.com:alberttluo/dotfiles.git`.

Note that `home/.zshrc.local.example` and the design docs reference internal
infrastructure — a license server host, a project codename, and local Windows
paths. Keep this repository private, or scrub those before making it public.
