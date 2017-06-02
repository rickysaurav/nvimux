local nvimux = {}
nvimux.debug = {}
nvimux.config = {}
nvimux.bindings = {}
nvimux.term = {}
nvimux.term.prompt = {}

--[[
Nvimux: Neovim as a terminal multiplexer.

This is the lua reimplementation of VimL.
--]]
-- luacheck: globals unpack


-- [ Private variables and tables
local nvim = vim.api -- luacheck: ignore
local consts = {
  terminal_quit = '<C-\\><C-n>',
  esc = '<ESC>',
}

local fns = {}
local nvim_proxy = {
  __index = function(table, key)
    local key_ = 'nvimux_' .. key
    local val = nil
    if fns.exists(key_) then
      val = nvim.nvim_get_var(key_)
      table[key] = val
    end
    return val
  end
}

local vars = {
  prefix = '<C-b>',
  vertical_split = ':NvimuxVerticalSplit',
  horizontal_split = ':NvimuxHorizontalSplit',
  quickterm_scope = 'g',
  quickterm_direction = 'botright',
  quickterm_orientation = 'vertical',
  quickterm_size = '',
  new_term = 'term',
  close_term = ':x'
}

vars.split_type = function(t)
  return t.quickterm_direction .. ' ' .. t.quickterm_orientation .. ' ' .. t.quickterm_size .. 'split'
end

-- [[ Table of default bindings
local bindings = {
  mappings = {
    ['<C-r>']  = { nvi  = {':so $MYVIMRC'}},
    ['!']      = { nvit = {':wincmd T'}},
    ['%']      = { nvit = {function() return vars.vertical_split end} },
    ['"']      = { nvit = {function() return vars.horizontal_split end}},
    ['q']      = { nvit = {':NvimuxToggleTerm'}},
    ['w']      = { nvit = {':tabs'}},
    ['o']      = { nvit = {'<C-w>w'}},
    ['n']      = { nvit = {'gt'}},
    ['p']      = { nvit = {'gT'}},
    ['x']      = { nvi  = {':bd %'},
                   t    = {function() return vars.close_term end}},
    ['X']      = { nvi  = {':enew \\| bd #'}},
    ['h']      = { nvit = {'<C-w><C-h>'}},
    ['j']      = { nvit = {'<C-w><C-j>'}},
    ['k']      = { nvit = {'<C-w><C-k>'}},
    ['l']      = { nvit = {'<C-w><C-l>'}},
    [':']      = { t    = {':'}},
    ['[']      = { t    = {''}},
    [']']      = { nvit = {':NvimuxTermPaste'}},
    [',']      = { t    = {'', nvimux.term.prompt.rename}},
    ['c']      = { nvit = {function() return ':tabe | ' .. vars.new_term end}},
    ['t']      = { nvit = {':tabe'}},
  },
  map_table    = {}
}

-- ]]

setmetatable(vars, nvim_proxy)

-- ]

-- [ Private functions
-- [[ keybind commands
fns.bind_fn = function(options)
    local prefix = options.prefix  or ''
    local mode = options.mode
  return function(key, command)
    local suffix = string.sub(command, 1, 1) == ':' and '<CR>' or ''
    nvim.nvim_command(mode .. 'noremap <silent> ' .. vars.prefix .. key .. ' ' .. prefix .. command .. suffix)
  end
end

fns.bind = {
  t = fns.bind_fn{mode = 't', prefix = consts.terminal_quit},
  i = fns.bind_fn{mode = 'i', prefix = consts.esc},
  n = fns.bind_fn{mode = 'n'},
  v = fns.bind_fn{mode = 'v'}
}

fns.bind._ = function(key, mapping, modes)
  for _, mode in ipairs(modes) do
    fns.bind[mode](key, mapping)
  end
end
-- ]]

-- [[ Commands and helper functions
fns.split = function(str)
  local p = {}
  for i=1, #str do
    table.insert(p, str:sub(i, i))
  end
  return p
end

fns.exists = function(var)
  return nvim.nvim_call_function('exists', {var}) == 1
end

fns.defn = function(var, val)
  if fns.exists(var) then
    nvim.nvim_set_var(var, val)
    return val
  else
    return nvim.nvim_get_var(var)
  end
end

fns.prompt = function(message)
  nvim.nvim_call_function('inputsave', {})
  local ret = nvim.nvim_call_function('input', {message})
  nvim.nvim_call_function('inputrestore', {})
  return ret
end
-- ]]

-- [[ Set var
fns.variables = {}
fns.variables.scoped = {
  arg = {
    b = function() return nvim.nvim_call_function('bufnr', {'%'}) end,
    t = function() return nvim.nvim_call_function('tabpagenr', {}) end,
    l = function() return nvim.nvim_call_function('winnr', {}) end,
    g = function() return nil end,
  },
  set = {
    b = function(options) return nvim.nvim_buf_set_var(options.nr, options.name, options.value) end,
    t = function(options) return nvim.nvim_tabpage_set_var(options.nr, options.name, options.value) end,
    l = function(options) return nvim.nvim_win_set_var(options.nr, options.name, options.value) end,
    g = function(options) return nvim.nvim_set_var(options.name, options.value) end,
  },
  get = {
    b = function(options) return nvim.nvim_buf_get_var(options.nr, options.name) end,
    t = function(options) return nvim.nvim_tabpage_get_var(options.nr, options.name) end,
    l = function(options) return nvim.nvim_win_get_var(options.nr, options.name) end,
    g = function(options) return nvim.nvim_get_var(options.name) end,
  },
}

fns.variables.set = function(options)
  local mode = options.mode or 'g'
  options.nr = options.nr or fns.variables.scoped.arg[mode]()
  fns.variables.scoped.set[mode](options)
end

fns.variables.get = function(options)
  local mode = options.mode or 'g'
  options.nr = options.nr or fns.variables.scoped.arg[mode]()
  return fns.variables.scoped.get[mode](options)
end

-- ]]
-- ]

-- [ Public API
-- [[ Config-handling commands
nvimux.config.set = function(options)
  vars[options.key] = options.value
  nvim.nvim_set_var('nvimux_' .. options.key, options.value)
end

nvimux.config.set_all = function(options)
  for key, value in pairs(options) do
    nvimux.config.set{['key'] = key, ['value'] = value}
  end
end
-- ]]

-- [[ Quickterm
nvimux.term.new_toggle = function()
  local split_type = vars:split_type()
  nvim.nvim_command(split_type .. ' | enew | ' .. vars.new_term)
  local buf_nr = nvim.nvim_call_function('bufnr', {'%'})
  nvim.nvim_set_option('wfw', true)
  fns.variables.set{mode='b', nr=buf_nr, name='nvimux_buf_orientation', value=split_type}
  fns.variables.set{mode=vars.quickterm_scope, name='nvimux_last_buffer_id', value=buf_nr}
end

nvimux.term.toggle = function()
  -- TODO Allow external commands
  print(vars.quickterm_scope)
  local buf_nr = fns.variables.get{mode=vars.quickterm_scope, name='nvimux_last_buffer_id'}
  print(buf_nr)
  if buf_nr == nil then
    nvimux.term.new_toggle()
  else
    local window = nvim.nvim_call_function('bufwinnr', {buf_nr})
    if window == -1 then
      if nvim.nvim_call_function('bufname', {buf_nr}) == '' then
        nvimux.term.new_toggle()
      else
        local split_type = nvim.nvim_buf_get_var(buf_nr, 'nvimux_buf_orientation')
        nvim.nvim_command(split_type .. ' | b' .. buf_nr)
      end
    else
      nvim.nvim_command(window .. ' wincmd w | q | stopinsert')
    end
  end
end

nvimux.term.prompt.rename = function()
  nvimux.term_only{
    cmd = fns.prompt('nvimux > New term name: '),
    action = function(k) nvim.nvim_command('file term://' .. k) end
  }
end
-- ]]

-- [[ Bindings
nvimux.bindings.bind = function(options)
  local override = 'nvimux_override_' .. options.key
  if fns.exists(override) then
    options.value = nvim.nvim_get_var(override)
  end
  fns.bind._(options.key, options.value, options.modes)
end

nvimux.bindings.bind_all = function(options)
  for _, bind in ipairs(options) do
    fns.bind._(unpack(bind))
  end
end

-- ]]

-- [[ Top-level commands
nvimux.debug.vars = function()
  for k, v in pairs(vars) do
    print(k, v)
  end
end

nvimux.debug.bindings = function()
  for k, v in pairs(bindings.mappings) do
    print(k, v)
  end
  print('')
  for k, v in pairs(bindings.map_table) do
    print(k, v)
  end
end

nvimux.term_only = function(options)
  local action = options.action or nvim.nvim_command
  if nvim.nvim_buf_get_option('%', 'buftype') == 'terminal' then
    action(options.cmd)
  else
    print("Not on terminal")
  end
end

nvimux.mapped = function(options)
  local mapping = bindings.map_table[options.key]
  local action = mapping.action or nvim.nvim_command
  if type(mapping.arg) == 'function' then
     action(mapping.arg())
  else
     action(mapping.arg)
  end
end
 -- ]]
-- ]

-- [ Runtime and warmup
for i=1, 9 do
  bindings.mappings[i] = { nvit = {i .. 'gt'}}
end

for key, cmd in pairs(bindings.mappings) do
  for modes, data in pairs(cmd) do
    modes = fns.split(modes)
    local arg, action = unpack(data)
    local binds = {
      ['key'] = key,
      ['modes'] = modes,
    }
    if type(arg) == 'function' or action ~= nil then
      bindings.map_table[key] = {['arg'] = arg, ['action'] = action}
      binds.value = ':lua nvimux.mapped{key = "' .. key .. '"}'
    else
      binds.value = arg
    end
    nvimux.bindings.bind(binds)
  end
end
-- ]

return nvimux
