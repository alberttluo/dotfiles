return {
  {
    "stevearc/conform.nvim",
    -- event = 'BufWritePre', -- uncomment for format on save
    opts = require "configs.conform",
  },

  -- These are some examples, uncomment them if you want to see them work!
  {
    "neovim/nvim-lspconfig",
    config = function()
      require "configs.lspconfig"
    end,
  },

  -- test new blink
  -- { import = "nvchad.blink.lazyspec" },

  {
    "tamton-aquib/duck.nvim",
    keys = {
      { "<leader>dh", function() require("duck").hatch("🦥", 12) end, desc = "Release a sloth" },
      { "<leader>dc", function() require("duck").cook() end, desc = "Remove nearest sloth" },
      { "<leader>dC", function() require("duck").cook_all() end, desc = "Remove all sloths" },
    },
  },

  {
    "gen740/SmoothCursor.nvim",
    event = "VeryLazy",
    config = function()
      require("smoothcursor").setup({
        fancy = { enable = true },
        speed = 25,
      })
    end,
  },

  {
    "nvim-treesitter/nvim-treesitter",
    -- Pinned, because nothing else pins it and the wrong branch is silently
    -- installable. master was archived at v0.10.0 and does not support Neovim
    -- 0.11+: its `set-lang-from-info-string!` directive indexes a match as one
    -- node per capture, but matches hold a list of nodes now, so every markdown
    -- buffer throws "attempt to call method 'range' (a nil value)" out of the
    -- conceal_line decoration provider. NvChad also calls
    -- require("nvim-treesitter").install(), which only exists on main.
    branch = "main",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "markdown", "markdown_inline" })
    end,
  },

  {
    -- Make external-change discovery deterministic instead of dependent on
    -- filesystem watchers.
    --
    -- Watchers are backed by inotify on Linux, and a direct uv.fs_event probe on a
    -- Windows-backed WSL mount (9p/DrvFs) never fires — so on those paths the tree
    -- has no watcher-based way to notice anything. nvim-tree also disables watchers
    -- outright after any watcher error, and inotify max_user_instances is finite.
    -- reload_on_bufenter defaults to false, which leaves nothing to fall back on.
    --
    -- Note: a stale tree was NOT reproducible on the WSL box during this change, so
    -- treat this as removing a dependency on watchers rather than a proven fix.
    "nvim-tree/nvim-tree.lua",
    opts = function(_, opts)
      opts.reload_on_bufenter = true
      opts.filesystem_watchers = vim.tbl_deep_extend("force", opts.filesystem_watchers or {}, {
        enable = true,
        debounce_delay = 50,
      })

      -- git.timeout defaults to 400ms. nvim-tree counts timeouts and, after 5,
      -- permanently disables git integration for the session with the warning
      -- "N git jobs have timed out after git.timeout 400ms, disabling git
      -- integration." On 9p/DrvFs mounts `git status` takes seconds, so that fires
      -- routinely.
      --
      -- The initial project load runs the git job synchronously, so a large timeout
      -- trades the warning for a freeze of the same length. Instead: modest headroom
      -- for normal filesystems, and skip git entirely where it cannot possibly meet
      -- the budget.
      opts.git = vim.tbl_deep_extend("force", opts.git or {}, {
        timeout = 1000,
        disable_for_dirs = function(path)
          return require("albert.slowfs").is_slow(path)
        end,
      })

      return opts
    end,
  },

  {
    -- find_files runs `fd --type f` with no flags, so it hides dotfiles and
    -- anything gitignored. A newly created file is then missing from the picker
    -- permanently, which reads as staleness. Showing hidden files fixes the
    -- dotfile half; gitignored files remain excluded on purpose so build and
    -- vendor directories do not swamp the list — use <leader>fa for those, which
    -- NvChad maps to find_files with no_ignore=true hidden=true.
    "nvim-telescope/telescope.nvim",
    opts = function(_, opts)
      opts.pickers = vim.tbl_deep_extend("force", opts.pickers or {}, {
        find_files = {
          hidden = true,
          -- --hidden would otherwise pull in the whole object database.
          file_ignore_patterns = { "^%.git/", "/%.git/" },
        },
      })
      return opts
    end,
  },

  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-tree/nvim-web-devicons",
    },
    opts = {
      -- Keep conceals active in normal/command-line mode so **bold** and table
      -- box-drawing stay rendered when the cursor is on their line.
      -- Plugin default is "" (always reveal on cursor line).
      win_options = {
        concealcursor = { rendered = "nc" },
      },
    },
  },
}
