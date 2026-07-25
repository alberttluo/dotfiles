require "nvchad.autocmds"

-- Pick up filesystem changes made by other processes (Claude Code, git, build
-- flows) without needing a manual refresh.
--
-- nvim-tree discovers external changes through libuv fs_event watchers, which are
-- backed by inotify on Linux. inotify does not work on Windows-backed WSL mounts
-- (9p/DrvFs): the handle starts successfully and then never fires, so the tree
-- silently goes stale with no error. Refreshing on focus and buffer events works
-- whether or not watchers function.
--
-- tmux is configured with `focus-events on`, so FocusGained fires when you switch
-- back to the nvim pane — precisely when a stale tree gets noticed.

vim.opt.autoread = true

local group = vim.api.nvim_create_augroup("ExternalChangeRefresh", { clear = true })

vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "TermLeave", "TermClose" }, {
  group = group,
  desc = "Reload the file tree and changed buffers after external changes",
  callback = function()
    -- checktime is meaningless for non-file buffers and can interrupt an edit in
    -- progress, so restrict it to normal mode on a real file.
    if vim.fn.mode() == "n" and vim.bo.buftype == "" then
      pcall(vim.cmd.checktime)
    end

    local ok, api = pcall(require, "nvim-tree.api")
    if ok and api.tree.is_visible() then
      api.tree.reload()
    end
  end,
})
