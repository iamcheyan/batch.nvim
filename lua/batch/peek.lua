-- lua/batch/peek.lua
-- 预览穿透（Peek Through）：在 Batch 脚本中原地预览环境变量、配置文件条目、调用脚本源码与子程序

local parser = require("batch.parser")

local M = {}

--- 判断文件是否可读
local function file_readable(path)
  if not path or path == "" then return false end
  return vim.fn.filereadable(path) == 1
end

--- 根据文件后缀判断 Neovim 文件类型
local function detect_filetype_by_path(path)
  local ext = path:match("%.([%w_%-]+)$")
  if not ext then return "text" end
  ext = ext:lower()
  if ext == "bat" or ext == "cmd" then
    return "dosbatch"
  elseif ext == "js" then
    return "javascript"
  elseif ext == "conf" or ext == "ini" then
    return "dosini"
  elseif ext == "cob" or ext == "cbl" or ext == "cpy" then
    return "cobol"
  elseif ext == "sh" or ext == "bash" then
    return "sh"
  elseif ext == "json" then
    return "json"
  elseif ext == "lua" then
    return "lua"
  end
  return "text"
end

--- 寻找项目根目录（基于 git 仓库、Makefile 或父级目录）
local function get_project_root(buf_dir)
  if not buf_dir or buf_dir == "" then
    return vim.fn.getcwd()
  end
  local current = vim.fs.normalize(buf_dir)
  local check = current
  for _ = 1, 6 do
    if vim.fn.isdirectory(check .. "/.git") == 1 or file_readable(check .. "/.git") or file_readable(check .. "/Makefile") then
      return check
    end
    local parent = vim.fs.dirname(check)
    if not parent or parent == check then break end
    check = parent
  end
  local basename = vim.fs.basename(current)
  if basename == "windows-batch" or basename == "scripts" or basename == "bin" then
    return vim.fs.dirname(current)
  end
  return current
end

--- 扫描并收集当前脚本可能关联的 .conf 配置文件
local function find_conf_files(bufnr, buf_dir)
  local conf_paths = {}
  local seen = {}

  local function add_conf(p)
    if p and p ~= "" then
      local norm = vim.fs.normalize(p)
      if not seen[norm] and file_readable(norm) then
        seen[norm] = true
        table.insert(conf_paths, norm)
      end
    end
  end

  -- 1. 扫描当前 buffer 中的文件名引用（如 CONFIG_FILE=%~dp0night-batch.conf 或 call ... foo.conf）
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for _, line in ipairs(lines) do
      for conf_name in line:gmatch("([%w_%-%.]+%.conf)") do
        add_conf(buf_dir .. "/" .. conf_name)
        add_conf(buf_dir .. "/../" .. conf_name)
      end
    end
  end

  -- 2. 扫描当前目录与父级目录的常规 conf 文件
  add_conf(buf_dir .. "/night-batch.conf")
  add_conf(buf_dir .. "/../night-batch.conf")

  -- 3. 扫描目录下的其他 *.conf 文件
  local glob_pattern = buf_dir .. "/*.conf"
  for _, p in ipairs(vim.fn.glob(glob_pattern, false, true)) do
    add_conf(p)
  end

  return conf_paths
end

--- 解析 .conf 文件的键值映射表
local function parse_conf_file(conf_path)
  local entries = {}
  if not file_readable(conf_path) then
    return entries
  end
  local lines = vim.fn.readfile(conf_path)
  for line_idx, line in ipairs(lines) do
    local trimmed = vim.trim(line)
    if trimmed ~= "" and not vim.startswith(trimmed, "#") and not vim.startswith(trimmed, ";") then
      local k, v = trimmed:match("^([%w_%-]+)%s*=%s*(.*)$")
      if k and v then
        entries[k:lower()] = {
          raw_key = k,
          raw_value = v,
          line = line_idx,
          conf_path = conf_path,
        }
      end
    end
  end
  return entries
end

--- 从指定行的某列提取单词
local function extract_word_at_col(line, col)
  if not line or line == "" then return "" end
  col = math.max(1, math.min(#line, col or 1))
  -- 向左寻找词首
  local s = col
  while s > 1 and line:sub(s - 1, s - 1):match("[%w_%-]") do
    s = s - 1
  end
  -- 向右寻找词尾
  local e = col
  while e < #line and line:sub(e + 1, e + 1):match("[%w_%-]") do
    e = e + 1
  end
  local word = line:sub(s, e)
  return word:match("^[%w_%-]+$") and word or ""
end

--- 从当前光标位置提取目标（变量、标签、文件路径）
function M.extract_target_under_cursor(line, col)
  line = line or vim.api.nvim_get_current_line()
  col = col or vim.fn.col(".") -- 1-based

  -- 1. 检查是否在标签调用中：goto :LABEL 或 call :LABEL
  local goto_target = line:match("[Gg][Oo][Tt][Oo]%s+:([%w_%-]+)")
    or line:match("[Cc][Aa][Ll][Ll]%s+:([%w_%-]+)")
  if goto_target then
    local word = extract_word_at_col(line, col)
    if word == goto_target or line:find(":" .. goto_target, 1, true) then
      return { type = "label", name = goto_target }
    end
  end

  -- 2. 检查光标处的带百分号环境变量：%VAR% 或 %~dp0
  for s, var_name, e in line:gmatch("()%%([%w_]+)%%()") do
    if col >= s and col <= e then
      return { type = "variable", name = var_name, raw = "%" .. var_name .. "%" }
    end
  end

  -- 3. 寻找包含当前光标位置的 !VAR!（延迟变量）
  for s, var_name, e in line:gmatch("()!([%w_]+)!()") do
    if col >= s and col <= e then
      return { type = "variable", name = var_name, raw = "!" .. var_name .. "!" }
    end
  end

  -- 4. 检查是否在 :label 定义行本身
  local def_label = line:match("^%s*:([%w_%-]+)")
  if def_label then
    return { type = "label", name = def_label }
  end

  -- 5. 回退到当前列单词并判断是否为已知变量或标签
  local word = extract_word_at_col(line, col)
  if word == "" then
    local ok, cw = pcall(vim.fn.expand, "<cword>")
    if ok and type(cw) == "string" then word = cw end
  end

  if word and word ~= "" then
    if word:match("^[A-Za-z_][A-Za-z0-9_%-]*$") then
      return { type = "variable", name = word, raw = "%" .. word .. "%" }
    end
  end

  return nil
end

--- 解析并生成变量的穿透预览数据
function M.resolve_variable_peek(bufnr, var_name)
  local buf_path = vim.api.nvim_buf_get_name(bufnr)
  local buf_dir = buf_path ~= "" and vim.fs.dirname(buf_path) or vim.fn.getcwd()
  local project_root = get_project_root(buf_dir)

  local var_lower = var_name:lower()
  local display_lines = {}
  local target_filetype = "dosbatch"
  local target_file_path = nil

  -- 1. 在当前脚本中搜索赋值语句
  local script_assignments = {}
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for idx, l in ipairs(lines) do
      local matched_var, matched_val = l:match("^[%s@]*[Ss][Ee][Tt]%s+[\"]*([%w_]+)%s*=%s*(.-)[\"]*%s*$")
      if matched_var and matched_var:lower() == var_lower then
        table.insert(script_assignments, { line = idx, expr = vim.trim(l), val = matched_val })
      end
    end
  end

  -- 2. 搜索配置文件中的条目
  local conf_paths = find_conf_files(bufnr, buf_dir)
  local conf_entry = nil
  for _, cp in ipairs(conf_paths) do
    local entries = parse_conf_file(cp)
    if entries[var_lower] then
      conf_entry = entries[var_lower]
      break
    end
    -- 如果脚本里 set "INPUT_FILE=%NIGHT_INPUT_FILE%"，顺藤摸瓜寻找所引用的来源变量
    if #script_assignments > 0 then
      for _, assign in ipairs(script_assignments) do
        local chained_var = assign.val:match("%%([%w_]+)%%") or assign.val:match("!([%w_]+)!")
        if chained_var and entries[chained_var:lower()] then
          conf_entry = entries[chained_var:lower()]
          break
        end
      end
    end
    if conf_entry then break end
  end

  -- 3. 确定最终解析的路径或字符串值
  local raw_value = nil
  if conf_entry then
    raw_value = conf_entry.raw_value
  elseif #script_assignments > 0 then
    raw_value = script_assignments[#script_assignments].val
  end

  local expanded_path = nil
  if raw_value then
    -- 展开 @ROOT@ 和 @DATE@
    local exp = raw_value:gsub("@ROOT@", project_root)
    exp = exp:gsub("@DATE@", os.date("%Y%m%d"))
    exp = exp:gsub("\\", "/")
    -- 去掉包裹引号
    exp = exp:gsub("^\"", ""):gsub("\"$", "")

    if file_readable(exp) then
      expanded_path = exp
    else
      -- 尝试相对 buf_dir 拼接
      local rel_buf = vim.fs.normalize(buf_dir .. "/" .. exp)
      if file_readable(rel_buf) then
        expanded_path = rel_buf
      end
    end
  end

  -- 4. 构建穿透预览浮窗内容
  local title = string.format(" [ 预览穿透: %%%s%% ] ", var_name)

  -- 头部元数据区域
  table.insert(display_lines, string.format("REM ─── 环境变量穿透元信息 ──────────────────────────────────────"))
  table.insert(display_lines, string.format("REM 变量名称: %%%s%%", var_name))

  if #script_assignments > 0 then
    for _, sa in ipairs(script_assignments) do
      table.insert(display_lines, string.format("REM 脚本赋值 (第 %d 行): %s", sa.line, sa.expr))
    end
  end

  if conf_entry then
    local rel_conf = conf_entry.conf_path:gsub("^" .. vim.pesc(project_root) .. "/?", "")
    table.insert(display_lines, string.format("REM 设定来源: %s:%d", rel_conf, conf_entry.line))
    table.insert(display_lines, string.format("REM 原始配置: %s=%s", conf_entry.raw_key, conf_entry.raw_value))
  end

  if expanded_path then
    target_file_path = expanded_path
    local rel_target = expanded_path:gsub("^" .. vim.pesc(project_root) .. "/?", "")
    target_filetype = detect_filetype_by_path(expanded_path)
    table.insert(display_lines, string.format("REM 穿透目标: %s", rel_target))
    table.insert(display_lines, string.format("REM ─── 目标脚本 / 文件代码实况 ───────────────────────────────"))

    -- 读取目标文件前 35 行代码展示穿透效果
    local target_lines = vim.fn.readfile(expanded_path, "", 35)
    for _, tl in ipairs(target_lines) do
      table.insert(display_lines, tl)
    end
  else
    if raw_value and raw_value ~= "" then
      table.insert(display_lines, string.format("REM 解析取值: %s", raw_value))
    else
      table.insert(display_lines, string.format("REM [提示] 当前脚本或配置文件中未找到该变量的静态赋值"))
    end
    table.insert(display_lines, string.format("REM ──────────────────────────────────────────────────────────"))
  end

  return {
    title = title,
    lines = display_lines,
    filetype = target_filetype,
    target_file = target_file_path,
  }
end

--- 解析并生成标签（Subroutine）的穿透预览数据
function M.resolve_label_peek(bufnr, label_name)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local parsed = parser.parse(lines)
  local label_item = parsed.labels[label_name:lower()]

  if not label_item then
    return nil
  end

  local start_line = label_item.line
  local preview_lines = {}
  table.insert(preview_lines, string.format("REM ─── 子程序/标签代码穿透 (第 %d 行) ───────────────────", start_line))

  local max_lines = 30
  local count = 0
  for i = start_line, math.min(#lines, start_line + max_lines) do
    local l = lines[i]
    -- 若遇到下一个标签且不是第一行，则截断
    if i > start_line and l:match("^%s*:[^:]") then
      break
    end
    table.insert(preview_lines, l)
    count = count + 1
  end

  return {
    title = string.format(" [ 预览穿透: :%s (第 %d 行) ] ", label_item.name, start_line),
    lines = preview_lines,
    filetype = "dosbatch",
  }
end

--- 打开完全不透明的现代浮动窗口
local function open_float_window(peek_data)
  if not peek_data or not peek_data.lines or #peek_data.lines == 0 then
    vim.notify("Batch: 未找到可预览的穿透内容", vim.log.levels.INFO)
    return nil
  end

  local lines = peek_data.lines
  local title = peek_data.title or " [ 预览穿透 ] "
  local filetype = peek_data.filetype or "dosbatch"

  -- 1. 创建 Scratch Buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = filetype

  -- 2. 计算浮窗尺寸（最大宽度 110，最大高度 26）
  local max_line_len = 0
  for _, line in ipairs(lines) do
    local w = vim.fn.strdisplaywidth(line)
    if w > max_line_len then max_line_len = w end
  end
  local width = math.min(110, math.max(45, max_line_len + 4))
  local height = math.min(26, math.max(3, #lines))

  local win_opts = {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
  }

  -- 边界检查：若光标下方空间不足，则向上弹出
  local current_win = vim.api.nvim_get_current_win()
  local win_height = vim.api.nvim_win_get_height(current_win)
  local cursor_win_row = vim.fn.winline()
  if cursor_win_row + height + 2 > win_height and cursor_win_row > height + 2 then
    win_opts.row = -(height + 2)
  end

  -- 3. 打开原生浮动窗口，设置 100% 实体背景防穿光
  local win = vim.api.nvim_open_win(buf, false, win_opts)
  vim.wo[win].winblend = 0 -- 100% 不透明，彻底阻挡底层文字透出
  vim.wo[win].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true

  -- 4. 注册快捷键与自动销毁机制
  local function close_window()
    if vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end

  -- 浮窗内按 q 或 <Esc> 关闭
  vim.keymap.set("n", "q", close_window, { buffer = buf, silent = true, nowait = true })
  vim.keymap.set("n", "<Esc>", close_window, { buffer = buf, silent = true, nowait = true })

  -- 若用户在浮窗内按 gd / 回车，且有穿透目标文件，直接跳转打开目标文件
  if peek_data.target_file and file_readable(peek_data.target_file) then
    vim.keymap.set("n", "<CR>", function()
      close_window()
      vim.cmd("edit " .. vim.fn.fnameescape(peek_data.target_file))
    end, { buffer = buf, silent = true, desc = "打开穿透目标文件" })
  end

  -- 主窗口光标一旦移动，或者切出 buffer，自动关闭浮窗
  local augroup = vim.api.nvim_create_augroup("BatchPeekAutoClose_" .. win, { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave", "WinLeave" }, {
    group = augroup,
    once = true,
    callback = function()
      close_window()
    end,
  })

  return win
end

--- 预览穿透主入口函数
function M.peek(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_get_current_line()
  local col = vim.fn.col(".")

  local target = M.extract_target_under_cursor(line, col)
  if not target then
    vim.notify("Batch: 光标处未检测到环境变量或标签", vim.log.levels.INFO)
    return nil
  end

  local peek_data = nil
  if target.type == "variable" then
    peek_data = M.resolve_variable_peek(bufnr, target.name)
  elseif target.type == "label" then
    peek_data = M.resolve_label_peek(bufnr, target.name)
  end

  if not peek_data then
    vim.notify("Batch: 无法解析 " .. tostring(target.name) .. " 的穿透信息", vim.log.levels.WARN)
    return nil
  end

  return open_float_window(peek_data)
end

return M
