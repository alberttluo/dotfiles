# Portable tmux + zsh + Claude Code Package — Design

**Date:** 2026-07-24
**Status:** Approved
**Repo:** `~/dotfiles` (`origin`: `git@github.com:alberttluo/dotfiles.git`)

## Goal

Reproduce the current terminal environment — tmux, zsh, Neovim, Claude Code, and fonts — on a
fresh macOS or Red Hat Linux machine by cloning one repo and running one script.

Non-goals: an uninstaller, secret management, syncing config changes back from other machines.

## Source Environment

Captured from the authoring machine (WSL2 Ubuntu, kernel 6.6.114.1) on 2026-07-24.

| Component | State |
|---|---|
| zsh | oh-my-zsh, `robbyrussell` theme, `plugins=(git)` |
| tmux | 3.6; oh-my-tmux (`gpakosz/.tmux` @ `af33f07`) symlinked from `~/.local/share/tmux/oh-my-tmux`; 525-line `~/.config/tmux/tmux.conf.local` |
| tmux plugins | tpm, `accessd/tmux-agent-indicator`, `laktak/extrakto` |
| Neovim | 0.12.2, NvChad v2.5 via lazy.nvim, `lazy-lock.json` present |
| Claude Code | `settings.json` (agent-indicator hooks, OMC HUD statusline, `opus[1m]`, `teammateMode: tmux`), 4 plugins across 3 marketplaces, 58 skills, `CLAUDE.md`, `.omc-config.json` |
| Fonts | JetBrainsMono Nerd Font, 96 files (NL / Mono / Propo variants) in `~/.local/share/fonts` |

`tmux.conf.local` and the Neovim config contain no OS-conditional logic — no `pbcopy`/`xclip`
branching, no `/mnt/c` paths. All machine-specific configuration is confined to `.zshrc`.

## Architecture

### Repository layout

```
dotfiles/
  install.sh                       # single entrypoint
  verify.sh                        # post-install assertions
  Brewfile
  lib/
    log.sh                         # step / ok / warn / fail
    os.sh                          # detect_os, brew bootstrap, brew_prefix
    link.sh                        # backup_and_link (idempotent)
  install/
    00-preflight.sh
    10-packages.sh
    20-fonts.sh
    30-zsh.sh
    40-tmux.sh
    50-nvim.sh
    60-claude.sh
    70-skills.sh
  home/
    .zshrc                         # portable only
    .zshenv
    .zshrc.local.example
  config/
    tmux/tmux.conf.local           # verbatim from source machine
    nvim/                          # full NvChad config incl. lazy-lock.json
  claude/
    settings.json
    CLAUDE.md
    .omc-config.json.template      # nodeBinary resolved at install time
    settings.local.json.example
    hud/                           # 5 vendored files, no cache/
  agents/
    .skill-lock.json               # provenance for all 61 skills
    skills/                        # all 61 skill dirs, vendored (820K)
    CLAUDE-SKILL-LINKS.txt         # the 59 names to symlink into ~/.claude/skills
```

### Three-layer configuration model

Layers load in order; each may override the previous.

**Layer 1 — Shared (committed, symlinked into `$HOME`).** Everything portable.

`home/.zshrc` contains, and only contains:

- `export ZSH="$HOME/.oh-my-zsh"`, `ZSH_THEME="robbyrussell"`, `plugins=(git)`, `source $ZSH/oh-my-zsh.sh`
- `brew shellenv` evaluated against a **dynamically resolved** prefix — `/opt/homebrew` on Apple
  Silicon, `/usr/local` on Intel macOS, `/home/linuxbrew/.linuxbrew` on Linux. The source machine
  hardcodes the Linux path; that is replaced.
- nvm bootstrap (`NVM_DIR`, `nvm.sh`, `bash_completion`), **deduplicated** — the source `.zshrc`
  loads nvm twice (lines 109–111 and 116–117).
- `export PATH="$HOME/.local/bin:$PATH"`
- `[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"` as the final line

`home/.zshenv` keeps `. "$HOME/.cargo/env"` but guarded with `[ -f ]`, since Rust may be absent.

Deliberately dropped: `export PATH="$PATH:/opt/nvim-linux-x86_64/bin"`. Neovim comes from
Homebrew, so that path is obsolete on every target.

**Layer 2 — Per-host (`~/.zshrc.local`, gitignored, seeded from `.zshrc.local.example`).**
Everything tied to a specific machine, license server, or corporate network:

- `MGLS_LICENSE_FILE`, `SALT_LICENSE_SERVER`
- `MTI_HOME`, `QUESTA_HOME`, and the Questa `PATH` additions
- `source .../Vivado/settings64.sh`, `FLEXLM_DIAGNOSTICS`, `XIL_CSE_LEGACY_LICENSE_LOOKUP`,
  `PILOT_BYPASS_INITIALIZATION_CHECK`, `XILINXD_LICENSE_FILE`, `XIL_LIC_BYPASS_VERSION_CHECK`,
  `XVV_ENABLE_NOLIC_MODE`
- `NODE_EXTRA_CA_CERTS` (Zscaler root cert)
- Aliases `cdh`, `cds`, `vsim`
- `alias claude='claude --dangerously-skip-permissions'`
- ssh-agent bootstrap

The ssh-agent line is rewritten. The source machine runs `eval "$(ssh-agent -s)"` unconditionally,
which spawns a fresh agent for every shell — one leaked process per tmux pane. The replacement
reuses a running agent and only starts one if `ssh-add -l` cannot reach an existing socket.

`--dangerously-skip-permissions` and `skipDangerousModePermissionPrompt` are per-host by design.
A new machine starts with permission prompts enabled; bypassing them is an explicit per-box opt-in
so the setting cannot silently land on a shared or production host.

**Layer 3 — Machine state (never packaged, never linked, gitignored).**
`~/.claude/.credentials.json`, `history.jsonl`, `projects/`, `session-env/`, `sessions/`,
`file-history/`, `paste-cache/`, `shell-snapshots/`, `hud/cache/`, `~/.claude.json`,
`~/.zsh_history`. The linker operates on an explicit allowlist of paths rather than globbing
`~/.claude`, so no future state directory can be captured by accident.

### Claude Code: vendored vs. re-fetched

Vendored in the repo:

- `settings.json` — with the agent-indicator hook paths changed from `~/.tmux/plugins/...` to the
  XDG location (see "tmux plugin directory" below)
- `CLAUDE.md`
- `.omc-config.json.template`
- `hud/` — the 5 real files (`omc-hud-cache.sh`, `find-node.sh`, `omc-hud.mjs`,
  `lib/config-dir.sh`, `lib/config-dir.mjs`), excluding `cache/`.
  **Installed by copy, not symlink** (revised 2026-07-25): the HUD writes
  per-session cache into `hud/cache/`, so linking the directory would make the
  repo the write target for runtime state — a direct violation of the
  "machine state never enters the repo" rule. Copying keeps the cache in
  `~/.claude/hud/cache`. The cost is that a change to the vendored HUD needs
  `./install.sh --only 60-claude` to propagate.
- All 61 skills, vendored wholesale (see "Skills" below)

Re-fetched on first launch:

- The 4 plugins (`oh-my-claudecode`, `superpowers` ×2, `rust-analyzer-lsp`). Claude Code installs
  these itself from the `extraKnownMarketplaces` entries already in `settings.json`.

#### Skills — revised 2026-07-24 after inspecting the source machine

The original design assumed skill content lived in `~/.claude/skills/` and split it into authored
(vendor) versus marketplace (re-fetch), pending a manual audit. Inspection disproved both premises:

- Every entry in `~/.claude/skills/` is a **symlink** into `~/.agents/skills/`, a shared
  skills directory used by many agent CLIs. That directory is the real content.
- `~/.agents/.skill-lock.json` (schema `version: 3`) records full provenance for all 61 skills, so
  no manual audit is needed. Grouped by upstream: `mattpocock/skills` 29, `firecrawl/firecrawl-workflows`
  16, `firecrawl/cli` 10, `firecrawl/skills` 4, `anthropics/skills` 1 (`pdf`),
  `vercel-labs/skills` 1 (`find-skills`).
- **No skill is locally authored.** The "authored skills only" set is empty, so that rule would
  have packaged nothing.
- 59 of the 61 are linked into `~/.claude/skills`; `pdf` and `find-skills` are deliberately not.

Revised approach: **vendor all of `~/.agents/skills/` plus the lock file** — 820K of markdown, which
makes the vendor-versus-refetch tradeoff moot — and have the installer recreate the symlink farm.
No skill-manager CLI is present on the source machine's PATH, so restoring by re-running the
upstream tool is not reproducible; vendoring is deterministic and works offline.

`agents/CLAUDE-SKILL-LINKS.txt` holds the exact 59 names to link, generated from the current machine
so `pdf` and `find-skills` stay unlinked. The installer links `~/.claude/skills/<name>` →
`~/.agents/skills/<name>` for each listed name, and is a no-op when the link already points there.

`hud/` is vendored as a deliberate exception to "re-fetch marketplace content." OMC's setup flow
creates it, but that flow runs *inside* Claude Code after first launch, which would leave
`statusLine` pointing at a missing script on a fresh machine.

### Two source-machine defects fixed as part of the work

**tmux plugin directory collision.** The source machine has tpm trees under *both*
`~/.tmux/plugins` and `~/.config/tmux/plugins`. The package standardizes on
`~/.config/tmux/plugins` — XDG, and consistent with where `tmux.conf` is already symlinked —
and sets `TMUX_PLUGIN_MANAGER_PATH` accordingly. `settings.json` hooks that reference
`~/.tmux/plugins/tmux-agent-indicator` are updated to resolve `TMUX_AGENT_INDICATOR_DIR` to the
XDG path; the existing `${TMUX_AGENT_INDICATOR_DIR:-...}` default in each hook makes this a
one-line change per hook.

**`.omc-config.json` hardcodes an absolute node path.**
`nodeBinary: /home/alluo/.nvm/versions/node/v24.16.0/bin/node` is dead on any other machine.
Shipped as a template; `60-claude.sh` substitutes the value from `command -v node`.

## Install Flow

`install.sh` sets `set -euo pipefail`, parses flags, then invokes each step as a function so that
`warn`-class failures do not abort the run.

Flags: `--dry-run` (print the plan, touch nothing), `--only <step>` (re-run one step),
`--skip-fonts`.

**OS detection resolves to `macos` or `linux`, not `macos` or `rhel`.** Homebrew supplies every
dependency, so the distribution is almost irrelevant, and a hard `rhel` gate would make the script
untestable on the WSL2 Ubuntu machine it is written on. RHEL-specific handling reduces to ensuring
Homebrew's prerequisites (`gcc`, `curl`, `file`) are installed.

| Step | Action | On failure |
|---|---|---|
| `00-preflight` | detect OS and arch; require `curl`, `git`; bootstrap Homebrew if absent; resolve `brew --prefix`; create `~/.dotfiles-backup/<ISO-timestamp>/` | hard fail |
| `10-packages` | `brew bundle --file=Brewfile` → zsh, tmux, git, neovim, node | hard fail |
| `20-fonts` | download pinned nerd-fonts `JetBrainsMono.zip`; extract to `~/Library/Fonts` (macOS) or `~/.local/share/fonts` (Linux); `fc-cache -f` on Linux only | warn |
| `30-zsh` | oh-my-zsh unattended (`RUNZSH=no CHSH=no KEEP_ZSHRC=yes`); link `.zshrc`, `.zshenv`; seed `~/.zshrc.local` from example if absent; attempt `chsh` | hard fail except `chsh` |
| `40-tmux` | clone `gpakosz/.tmux` @ `af33f07` to `~/.local/share/tmux/oh-my-tmux`; symlink `~/.config/tmux/tmux.conf` → it; link `tmux.conf.local`; clone tpm; run `tpm/bin/install_plugins` | warn on plugin install |
| `50-nvim` | link `~/.config/nvim`; `nvim --headless "+Lazy! restore" +qa` | warn |
| `60-claude` | install Claude Code (`npm install -g @anthropic-ai/claude-code`, using the Homebrew node from `10-packages`); link `settings.json` and `CLAUDE.md`; **copy** `hud/`; render `.omc-config.json` from template; seed `settings.local.json` from example | hard fail |
| `70-skills` | copy `agents/skills/` → `~/.agents/skills/` and the lock file → `~/.agents/.skill-lock.json`; recreate the 59 symlinks in `~/.claude/skills` from `CLAUDE-SKILL-LINKS.txt` | warn |

`Lazy! restore` rather than `Lazy! sync` — restore honors `lazy-lock.json`, so plugin versions
match the source machine exactly.

Fonts install through a single code path on both operating systems (release zip, not a Homebrew
cask) because casks are macOS-only and one path is less to keep in sync.

`chsh -s "$(brew --prefix)/bin/zsh"` requires the shell to be listed in `/etc/shells` and may be
blocked outright on an LDAP-managed corporate host. The step appends to `/etc/shells` if it has
sudo, attempts `chsh`, and on failure prints both the manual command and an `exec zsh` fallback
line for `.bashrc`. This never fails the install.

**Idempotency.** Every step is a no-op when already satisfied. Anything displaced is moved to
`~/.dotfiles-backup/<ISO-timestamp>/` before linking — never deleted, never overwritten in place.

**Output.** Each step prints `▶ step`, then `✓` / `⚠` / `✗`. The run closes with a summary listing
what was installed, what was already present, every warning, and the manual follow-ups: run
`claude` to authenticate, fill in `~/.zshrc.local`, and `chsh` if it was skipped. Exit status is
non-zero only for hard failures.

**Not automatable.** Claude Code authentication. `.credentials.json` is never packaged; the script
instructs the user to run `claude` and log in.

## Verification

`verify.sh` is a separate script so it can be run independently of an install.

- `zsh -ic 'exit'` exits 0 — catches a `.zshrc` that errors on a machine lacking the EDA tools,
  which is the most likely regression from the layering split
- `tmux -f ~/.config/tmux/tmux.conf new-session -d` succeeds, then `kill-session`
- `extrakto` and `tmux-agent-indicator` are present under `~/.config/tmux/plugins`
- `fc-list | grep -c JetBrainsMono` ≥ 90 on Linux; `~/Library/Fonts` populated on macOS
- `nvim --headless +qa` exits 0 and `git diff --exit-code config/nvim/lazy-lock.json` is clean
- `claude --version` runs; `settings.json` parses as JSON; the `nodeBinary` path in
  `.omc-config.json` exists and is executable; `hud/omc-hud-cache.sh` is executable
- no linked path under `~/.claude` resolves into machine state (`credentials`, `history`,
  `projects`, `session-env`)
- `~/.claude/skills` contains exactly the 59 names in `CLAUDE-SKILL-LINKS.txt`, each a symlink
  resolving to an existing directory under `~/.agents/skills`; `pdf` and `find-skills` are present
  in `~/.agents/skills` but absent from `~/.claude/skills`

## Testing Strategy

**Linux / RHEL — executed.** The full install runs in a `rockylinux:9` container as a non-root
user with sudo, a fair approximation of a fresh corporate host. This is the primary test target
and exercises the Homebrew-on-Linux bootstrap, its build prerequisites, `fc-cache`, and `chsh`
behavior. `verify.sh` must pass in the container.

**macOS — reviewed, not executed.** No Mac is available to the implementer. macOS correctness rests
on `shellcheck` across all scripts plus review of the three divergent branches: `brew --prefix`
(`/opt/homebrew` vs `/usr/local` vs `/home/linuxbrew/.linuxbrew`), font destination
(`~/Library/Fonts`), and skipping `fc-cache`. This is a known gap, stated plainly: the first real
macOS run should use `--dry-run`.

**Static checks.** `shellcheck` over `install.sh`, `verify.sh`, `lib/*.sh`, `install/*.sh`.
