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
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "markdown", "markdown_inline" })
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
