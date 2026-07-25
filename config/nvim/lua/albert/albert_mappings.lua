vim.g.mapleader = " "

local keymap = vim.keymap

keymap.set("i", "jk", "<ESC>", { desc = "Exit insert mode with jk" })

keymap.set("n", "<leader>nh", ":nohl<CR>", { desc = "Clear search highlights" })

keymap.set("n", "<leader>+", "<C-a>", { desc = "Increment number" })
keymap.set("n", "<leader>-", "<C-x>", { desc = "Decrement number" })

keymap.set("n", "<leader>sv", "<C-w>v", { desc = "Split window vertically" })
keymap.set("n", "<leader>sh", "<C-w>s", { desc = "Split window horizontally" })
keymap.set("n", "<leader>se", "<C-w>=", { desc = "Make splits equal size" })
keymap.set("n", "<leader>sx", "<cmd>close<CR>", { desc = "Close current split" })

keymap.set("n", "<leader>to", "<cmd>tabnew<CR>", { desc = "Open new tab" })
keymap.set("n", "<leader>tx", "<cmd>tabclose<CR>", { desc = "Close current tab" })
keymap.set("n", "<leader>tn", "<cmd>tabn<CR>", { desc = "Go to next tab" })
keymap.set("n", "<leader>tp", "<cmd>tabp<CR>", { desc = "Go to previous tab" })
keymap.set("n", "<leader>tf", "<cmd>tabnew<CR>", { desc = "Open current buffer in new tab" })

-- File explorer toggle (replaces NvChad's <leader>e focus binding so <leader>ef is instant)
pcall(vim.keymap.del, "n", "<leader>e")
keymap.set("n", "<leader>ef", "<cmd>NvimTreeToggle<CR>", { desc = "Toggle file explorer" })

-- Anchor fuzzy find at the git root of the current buffer so parent files
-- (e.g. ../../test.txt) are reachable. Falls back to cwd outside a repo.
local function project_root()
  local file = vim.api.nvim_buf_get_name(0)
  local start = file ~= "" and vim.fn.fnamemodify(file, ":p:h") or vim.fn.getcwd()
  local git_dir = vim.fn.finddir(".git", start .. ";")
  if git_dir ~= "" then
    return vim.fn.fnamemodify(git_dir, ":p:h:h")
  end
  return vim.fn.getcwd()
end

keymap.set("n", "<leader>ff", function()
  require("telescope.builtin").find_files({ cwd = project_root(), hidden = true })
end, { desc = "Find files (project root)" })

keymap.set("n", "<leader>fw", function()
  require("telescope.builtin").live_grep({ cwd = project_root() })
end, { desc = "Live grep (project root)" })
