-- The colors of the current god for Neovim (modules/neovim.nix installs this as
-- colors/@id@.lua). They come from tokens.json, which the theme engine writes:
-- the session's (another god every 10 minutes) first, else the machine's.
-- Colors a theme from outside may lack fall back to the ten every theme has.

local function read(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local text = file:read("*a")
  file:close()
  local ok, value = pcall(vim.json.decode, text)
  if ok and type(value) == "table" and type(value.colors) == "table" then
    return value
  end
  return nil
end

local runtime = vim.env.XDG_RUNTIME_DIR
local tokens = (runtime and read(runtime .. "/@id@/theme/tokens.json")) or read("@runtimeDir@/tokens.json")
if not tokens then
  vim.notify("@name@: no theme found, keeping the colors as they are", vim.log.levels.WARN)
  return
end

local c = tokens.colors
local term = tokens.terminal or {}
local function pick(...)
  for _, name in ipairs({ ... }) do
    if c[name] then
      return c[name]
    end
  end
end

local p = {
  bg = c.background,
  surface = c.surface,
  raised = pick("surface-raised", "surface"),
  sunken = pick("surface-sunken", "background"),
  border = c.border,
  strong = pick("border-strong", "text-muted"),
  text = c.text,
  muted = c["text-muted"],
  faint = pick("text-faint", "text-muted"),
  accent = c.accent,
  on_accent = c["on-accent"],
  accent_text = pick("accent-text", "accent"),
  accent_soft = pick("accent-soft", "surface"),
  focus = c.focus,
  error = c.error,
  warning = c.warning,
  success = pick("success", "accent"),
  info = pick("info", "focus"),
  selection = term.selection or pick("accent-soft", "surface"),
  keyword = pick("syntax-keyword", "accent-text", "accent"),
  string = pick("syntax-string", "text"),
  number = pick("syntax-number", "warning"),
  func = pick("syntax-function", "text"),
  type = pick("syntax-type", "focus"),
  constant = pick("syntax-constant", "accent-text", "accent"),
  comment = pick("syntax-comment", "text-muted"),
  operator = pick("syntax-operator", "text-muted"),
}

vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then
  vim.cmd("syntax reset")
end
vim.o.background = tokens.appearance == "light" and "light" or "dark"
vim.o.termguicolors = true
vim.g.colors_name = "@id@"

local groups = {
  Normal = { fg = p.text, bg = p.bg },
  NormalNC = { fg = p.text, bg = p.bg },
  NormalFloat = { fg = p.text, bg = p.raised },
  FloatBorder = { fg = p.border, bg = p.raised },
  FloatTitle = { fg = p.text, bg = p.raised, bold = true },
  WinSeparator = { fg = p.border },
  ColorColumn = { bg = p.surface },
  Cursor = { fg = p.bg, bg = p.accent },
  CursorLine = { bg = p.surface },
  CursorColumn = { bg = p.surface },
  CursorLineNr = { fg = p.accent_text, bold = true },
  LineNr = { fg = p.faint },
  SignColumn = { fg = p.faint },
  FoldColumn = { fg = p.faint },
  Folded = { fg = p.muted, bg = p.surface },
  Visual = { bg = p.selection },
  Search = { fg = p.text, bg = p.accent_soft },
  IncSearch = { fg = p.on_accent, bg = p.accent },
  CurSearch = { fg = p.on_accent, bg = p.accent },
  Substitute = { fg = p.on_accent, bg = p.accent },
  MatchParen = { fg = p.accent_text, bold = true, underline = true },
  NonText = { fg = p.faint },
  Whitespace = { fg = p.border },
  SpecialKey = { fg = p.faint },
  EndOfBuffer = { fg = p.bg },
  Conceal = { fg = p.faint },
  Directory = { fg = p.type },
  Title = { fg = p.text, bold = true },
  Pmenu = { fg = p.text, bg = p.raised },
  PmenuSel = { fg = p.text, bg = p.selection, bold = true },
  PmenuSbar = { bg = p.surface },
  PmenuThumb = { bg = p.strong },
  PmenuKind = { fg = p.type, bg = p.raised },
  PmenuExtra = { fg = p.muted, bg = p.raised },
  StatusLine = { fg = p.text, bg = p.surface },
  StatusLineNC = { fg = p.faint, bg = p.surface },
  TabLine = { fg = p.muted, bg = p.surface },
  TabLineSel = { fg = p.text, bg = p.bg, bold = true },
  TabLineFill = { bg = p.surface },
  WildMenu = { fg = p.text, bg = p.selection },
  ModeMsg = { fg = p.muted },
  MoreMsg = { fg = p.success },
  Question = { fg = p.info },
  ErrorMsg = { fg = p.error },
  WarningMsg = { fg = p.warning },
  QuickFixLine = { bg = p.selection },
  DiffAdd = { bg = p.surface, fg = p.success },
  DiffChange = { bg = p.surface, fg = p.warning },
  DiffDelete = { bg = p.surface, fg = p.error },
  DiffText = { bg = p.selection, fg = p.text },
  Added = { fg = p.success },
  Changed = { fg = p.warning },
  Removed = { fg = p.error },
  SpellBad = { undercurl = true, sp = p.error },
  SpellCap = { undercurl = true, sp = p.warning },
  SpellLocal = { undercurl = true, sp = p.info },
  SpellRare = { undercurl = true, sp = p.info },

  Comment = { fg = p.comment, italic = true },
  Constant = { fg = p.constant },
  String = { fg = p.string },
  Character = { fg = p.string },
  Number = { fg = p.number },
  Boolean = { fg = p.constant },
  Float = { fg = p.number },
  Identifier = { fg = p.text },
  Function = { fg = p.func },
  Statement = { fg = p.keyword },
  Conditional = { fg = p.keyword },
  Repeat = { fg = p.keyword },
  Label = { fg = p.keyword },
  Operator = { fg = p.operator },
  Keyword = { fg = p.keyword },
  Exception = { fg = p.keyword },
  PreProc = { fg = p.keyword },
  Include = { fg = p.keyword },
  Define = { fg = p.keyword },
  Macro = { fg = p.constant },
  Type = { fg = p.type },
  StorageClass = { fg = p.keyword },
  Structure = { fg = p.type },
  Typedef = { fg = p.type },
  Special = { fg = p.accent_text },
  SpecialChar = { fg = p.number },
  Tag = { fg = p.keyword },
  Delimiter = { fg = p.operator },
  SpecialComment = { fg = p.comment, bold = true },
  Underlined = { underline = true },
  Error = { fg = p.error },
  Todo = { fg = p.bg, bg = p.warning, bold = true },

  DiagnosticError = { fg = p.error },
  DiagnosticWarn = { fg = p.warning },
  DiagnosticInfo = { fg = p.info },
  DiagnosticHint = { fg = p.muted },
  DiagnosticOk = { fg = p.success },
  DiagnosticUnderlineError = { undercurl = true, sp = p.error },
  DiagnosticUnderlineWarn = { undercurl = true, sp = p.warning },
  DiagnosticUnderlineInfo = { undercurl = true, sp = p.info },
  DiagnosticUnderlineHint = { undercurl = true, sp = p.muted },
  LspReferenceText = { bg = p.surface },
  LspReferenceRead = { bg = p.surface },
  LspReferenceWrite = { bg = p.surface, underline = true },
  LspInlayHint = { fg = p.faint },

  ["@variable"] = { fg = p.text },
  ["@variable.builtin"] = { fg = p.constant },
  ["@variable.parameter"] = { fg = p.text, italic = true },
  ["@variable.member"] = { fg = p.text },
  ["@property"] = { fg = p.text },
  ["@constant"] = { link = "Constant" },
  ["@constant.builtin"] = { fg = p.constant },
  ["@module"] = { fg = p.type },
  ["@string"] = { link = "String" },
  ["@string.escape"] = { fg = p.number },
  ["@string.special"] = { fg = p.number },
  ["@number"] = { link = "Number" },
  ["@boolean"] = { link = "Boolean" },
  ["@function"] = { link = "Function" },
  ["@function.builtin"] = { fg = p.func, italic = true },
  ["@function.call"] = { fg = p.func },
  ["@function.method"] = { fg = p.func },
  ["@constructor"] = { fg = p.type },
  ["@keyword"] = { link = "Keyword" },
  ["@keyword.return"] = { fg = p.keyword, bold = true },
  ["@operator"] = { link = "Operator" },
  ["@punctuation"] = { fg = p.operator },
  ["@type"] = { link = "Type" },
  ["@type.builtin"] = { fg = p.type, italic = true },
  ["@attribute"] = { fg = p.constant },
  ["@tag"] = { fg = p.keyword },
  ["@tag.attribute"] = { fg = p.type },
  ["@tag.delimiter"] = { fg = p.operator },
  ["@comment"] = { link = "Comment" },
  ["@markup.heading"] = { fg = p.text, bold = true },
  ["@markup.strong"] = { bold = true },
  ["@markup.italic"] = { italic = true },
  ["@markup.link"] = { fg = p.info, underline = true },
  ["@markup.raw"] = { fg = p.string },
  ["@markup.list"] = { fg = p.accent_text },
  ["@diff.plus"] = { fg = p.success },
  ["@diff.minus"] = { fg = p.error },
  ["@diff.delta"] = { fg = p.warning },
}
for name, spec in pairs(groups) do
  vim.api.nvim_set_hl(0, name, spec)
end

-- :terminal in the terminal colors of the theme
for index, color in ipairs(term.palette or {}) do
  vim.g["terminal_color_" .. (index - 1)] = color
end
