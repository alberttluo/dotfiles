-- Detect mount points whose filesystem cannot service nvim-tree's git budget.
--
-- On WSL, Windows drives are mounted over 9p/DrvFs. `git status --porcelain
-- --ignored --untracked-files=all` — the form nvim-tree issues — takes 2-4s on a
-- few hundred files there, against nvim-tree's default git.timeout of 400ms. After
-- MAX_TIMEOUTS (5) such jobs nvim-tree disables git integration for the session and
-- warns, which is the recurring "disabling git integration" message.
--
-- Raising git.timeout is the wrong remedy: the initial project load calls the git
-- runner without a callback, so it blocks on `vim.wait` until the timeout. A 4s
-- timeout converts a warning into a 4s freeze every time the tree opens in such a
-- repo. Not attempting git integration on those mounts is both faster and quiet.
--
-- Returns false everywhere on macOS and native Linux, where nothing matches.

local M = {}

-- Filesystems that back Windows drives under WSL.
local SLOW_FSTYPES = {
  ["9p"] = true,
  ["v9fs"] = true,
  ["drvfs"] = true,
}

local slow_mounts

local function detect()
  local mounts = {}
  local handle = io.open("/proc/mounts", "r")
  if not handle then
    return mounts -- no procfs: macOS, or a kernel without it
  end
  for line in handle:lines() do
    local point, fstype = line:match("^%S+%s+(%S+)%s+(%S+)")
    if point and SLOW_FSTYPES[fstype] then
      -- /proc/mounts octal-escapes spaces and tabs in mount points
      point = point:gsub("\\040", " "):gsub("\\011", "\t")
      table.insert(mounts, point)
    end
  end
  handle:close()
  return mounts
end

---@param path string absolute path
---@return boolean
function M.is_slow(path)
  if type(path) ~= "string" or path == "" then
    return false
  end
  slow_mounts = slow_mounts or detect()
  for _, mount in ipairs(slow_mounts) do
    if path == mount or path:sub(1, #mount + 1) == mount .. "/" then
      return true
    end
  end
  return false
end

---Exposed for inspection: :lua print(vim.inspect(require("albert.slowfs").mounts()))
---@return string[]
function M.mounts()
  slow_mounts = slow_mounts or detect()
  return slow_mounts
end

return M
