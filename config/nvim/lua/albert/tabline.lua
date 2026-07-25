-- Custom tabline: shows vim tabs labeled by file, horizontally centered in the bar.
local M = {}

function _G.AlbertTabline()
  local parts = {}
  local total = 0
  local current = vim.fn.tabpagenr()
  local last = vim.fn.tabpagenr("$")

  for i = 1, last do
    local winnr = vim.fn.tabpagewinnr(i)
    local buflist = vim.fn.tabpagebuflist(i)
    local bufnr = buflist[winnr]
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    local filename = bufname == "" and "[No Name]" or vim.fn.fnamemodify(bufname, ":t")
    local modified = vim.bo[bufnr].modified and " ●" or ""
    local label = "  " .. i .. " " .. filename .. modified .. "  "
    local hl = (i == current) and "%#AlbertTabSel#" or "%#TabLine#"
    table.insert(parts, hl .. "%" .. i .. "T" .. label)
    total = total + vim.fn.strdisplaywidth(label)
  end

  local pad = math.max(0, math.floor((vim.o.columns - total) / 2))
  local left = "%#TabLineFill#" .. string.rep(" ", pad)
  return left .. table.concat(parts) .. "%#TabLineFill#%T"
end

-- Pastel highlight for the active tab. Defined as our own group so the theme
-- (base46) doesn't override it; re-applied on ColorScheme to survive theme switches.
local function set_hl()
  vim.api.nvim_set_hl(0, "AlbertTabSel", { fg = "#1e1e2e", bg = "#b4befe", bold = true })
end

function M.setup()
  vim.opt.tabline = "%!v:lua.AlbertTabline()"
  vim.opt.showtabline = 2
  set_hl()
  vim.api.nvim_create_autocmd("ColorScheme", { callback = set_hl })
end

M.setup()
return M
