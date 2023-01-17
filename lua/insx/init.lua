local Keymap = require('insx.kit.Vim.Keymap')
local Runner = require('insx.Runner')

---@param char string
---@return insx.Context
local function context(char)
  return {
    filetype = vim.api.nvim_buf_get_option(0, 'filetype'),
    char = char,
    data = {},
    row = function()
      return vim.api.nvim_win_get_cursor(0)[1] - 1
    end,
    col = function()
      return vim.api.nvim_win_get_cursor(0)[2]
    end,
    text = function()
      return vim.api.nvim_get_current_line()
    end,
    before = function()
      local c = vim.api.nvim_win_get_cursor(0)[2]
      return vim.api.nvim_get_current_line():sub(1, c)
    end,
    after = function()
      local c = vim.api.nvim_win_get_cursor(0)[2]
      return vim.api.nvim_get_current_line():sub(c + 1)
    end,
  }
end

---@param key string
---@return string
local function normalize(key)
  return vim.fn.keytrans(Keymap.termcodes(key))
end

local insx = {}

insx.helper = require('insx.helper')

---@class insx.RecipeSource
---@field public action fun(ctx: insx.ActionContext): nil
---@field public enabled? fun(ctx: insx.Context): boolean
---@field public priority? integer

---@class insx.Context
---@field public filetype string
---@field public char string
---@field public data table
---@field public row fun(): integer 0-origin index
---@field public col fun(): integer 0-origin utf8 byte index
---@field public text fun(): string
---@field public after fun(): string
---@field public before fun(): string

---@class insx.ActionContext : insx.Context
---@field public send fun(keys: insx.kit.Vim.Keymap.KeysSpecifier): nil
---@field public move fun(row: integer, col: integer): nil

---@class insx.Recipe
---@field public index integer
---@field public action fun(ctx: insx.ActionContext): nil
---@field public enabled fun(ctx: insx.Context): boolean
---@field public priority integer

---@type table<string, insx.Recipe[]>
insx.recipes = {}

---Add new mapping recipe for specific mapping.
---@param char string
---@param recipe_source insx.RecipeSource
function insx.add(char, recipe_source)
  char = normalize(char)

  -- initialize mapping.
  if not insx.recipes[char] then
    insx.recipes[char] = {}

    vim.keymap.set('i', char, function()
      return insx.expand(char)
    end, {
      expr = true,
      replace_keycodes = false,
    })
  end

  -- add normalized recipe.
  table.insert(insx.recipes[char], {
    index = #insx.recipes[char] + 1,
    action = recipe_source.action,
    enabled = recipe_source.enabled or function()
      return true
    end,
    priority = recipe_source.priority,
  })
end

---Expand key mapping as cmd mapping.
---@param char string
---@return string
function insx.expand(char)
  char = normalize(char)

  local ctx = context(char)
  local r = insx.get_recipe(ctx)
  if r then
    return Keymap.to_sendable(function()
      Runner.new(ctx, r):run()
    end)
  end
  return Keymap.termcodes(char)
end

---Get sorted/normalized entries for specific mapping.
---@param ctx insx.Context
---@return insx.Recipe|nil
function insx.get_recipe(ctx)
  local recipes = insx.recipes[ctx.char] or {}
  table.sort(recipes, function(a, b)
    if a.priority and b.priority then
      local diff = a.priority - b.priority
      if diff == 0 then
        return a.priority > b.priority
      end
    end
    return a.index < b.index
  end)
  for _, recipe in ipairs(recipes) do
    if recipe.enabled(ctx) then
      return recipe
    end
  end
end

return insx