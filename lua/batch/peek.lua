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

--- 智能多路径与跨盘符文件解析器
--- 针对 Windows 脚本中跨盘符（如 C:\ops\...）、%~dp0 相对目录、@ROOT@ 宏及本地调试拷贝路径进行多路径候选探测
local function resolve_candidate_file(raw_value, buf_dir, project_root)
  if not raw_value or raw_value == "" then return nil, nil end

  -- 1. 去除包裹引号与首尾空白
  local clean = vim.trim(raw_value):gsub("^\"", ""):gsub("\"$", "")

  -- 2. 展开常见的 Batch 宏与参数修饰符并统一反斜杠
  local exp = clean
  if buf_dir and buf_dir ~= "" then
    exp = exp:gsub("%%~dp0", buf_dir .. "/")
  end
  exp = exp:gsub("%%~[a-zA-Z]*%d*", "")
  exp = exp:gsub("@ROOT@", project_root)
  exp = exp:gsub("@DATE@", os.date("%Y%m%d"))
  exp = exp:gsub("\\", "/")

  -- 直接命中本地真实文件
  if file_readable(exp) then
    return vim.fs.normalize(exp), "direct"
  end

  -- 3. 去掉 Windows 盘符（如 C:/ops/foo.bat -> ops/foo.bat）
  local no_drive = exp:gsub("^[A-Za-z]:[/\\]*", "")

  -- 4. 提取纯文件名（basename）
  local filename = vim.fs.basename(no_drive)
  if not filename or filename == "" then return nil, nil end

  -- 5. 多路径候选列表依次查找（当前目录、项目根目录、常见子目录）
  local candidates = {
    project_root .. "/" .. no_drive,
    buf_dir .. "/" .. no_drive,
    buf_dir .. "/" .. filename,
    buf_dir .. "/../" .. filename,
    project_root .. "/" .. filename,
    project_root .. "/windows-batch/" .. filename,
    project_root .. "/scripts/" .. filename,
    project_root .. "/scripts/linux/" .. filename,
    project_root .. "/scripts/windows/" .. filename,
    project_root .. "/data/" .. filename,
    project_root .. "/data/input/" .. filename,
    project_root .. "/data/output/" .. filename,
    project_root .. "/bin/" .. filename,
    project_root .. "/conf/" .. filename,
    project_root .. "/config/" .. filename,
    project_root .. "/etc/" .. filename,
    project_root .. "/src/" .. filename,
    project_root .. "/cobol-workbook/" .. filename,
    project_root .. "/cobol-workbook/src/" .. filename,
    project_root .. "/cobol-workbook/data/input/" .. filename,
    project_root .. "/cobol-workbook/data/output/" .. filename,
  }

  local seen = {}
  for _, cand in ipairs(candidates) do
    local norm = vim.fs.normalize(cand)
    if not seen[norm] then
      seen[norm] = true
      if file_readable(norm) then
        return norm, "candidate"
      end
    end
  end

  -- 6. 最终兜底：利用 Neovim 内置的 vim.fs.find 在项目目录树中进行广度优先搜索
  local found = vim.fs.find(filename, { path = project_root, upward = false, type = "file", limit = 1 })
  if found and #found > 0 and file_readable(found[1]) then
    return vim.fs.normalize(found[1]), "search"
  end

  return nil, nil
end

--- 扫描并收集当前脚本可能关联的 .conf 配置文件（包含跨盘符路径智能解析）
local function find_conf_files(bufnr, buf_dir, project_root)
  local conf_paths = {}
  local seen = {}

  local function add_conf(p)
    if p and p ~= "" then
      local matched, _ = resolve_candidate_file(p, buf_dir, project_root)
      if matched and not seen[matched] then
        seen[matched] = true
        table.insert(conf_paths, matched)
      end
    end
  end

  -- 1. 扫描当前 buffer 中的文件名引用（如 CONFIG_FILE=%~dp0night-batch.conf 或 call ... C:\ops\night-batch.conf）
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for _, line in ipairs(lines) do
      -- 匹配 *.conf 文件名或完整路径（兼容 %~dp0 与 Windows 盘符）
      for conf_ref in line:gmatch("([%w_%-%.\\/:~%%]+%.conf)") do
        add_conf(conf_ref)
      end
    end
  end

  -- 2. 常规配置探测
  add_conf("night-batch.conf")
  add_conf("batch.conf")

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
  local s = col
  while s > 1 and line:sub(s - 1, s - 1):match("[%w_%-]") do
    s = s - 1
  end
  local e = col
  while e < #line and line:sub(e + 1, e + 1):match("[%w_%-]") do
    e = e + 1
  end
  local word = line:sub(s, e)
  return word:match("^[%w_%-]+$") and word or ""
end

--- 提取光标所在位置的候选路径或文件名 token
local function extract_path_token_at_col(line, col)
  if not line or line == "" then return "" end
  col = math.max(1, math.min(#line, col or 1))

  -- 分隔符：空白、双引号、单引号、等号、逗号、分号、尖括号、管道、圆括号
  local is_delim = function(c)
    return c:match("[%s\"'=,;<>&|%(%)]") ~= nil
  end

  local ch = line:sub(col, col)
  if is_delim(ch) then
    return ""
  end

  local s = col
  while s > 1 and not is_delim(line:sub(s - 1, s - 1)) do
    s = s - 1
  end

  local e = col
  while e < #line and not is_delim(line:sub(e + 1, e + 1)) do
    e = e + 1
  end

  return line:sub(s, e)
end

--- 判定一个 token 是否为有效的文件名或路径候选
local function is_file_token(token)
  if not token or token == "" then return false end
  -- 排除纯批处理参数如 %~1, %1, %~dp0 单独出现
  if token:match("^%%~?%w+$") then
    return false
  end
  -- 包含文件扩展名 (例如 .conf, .bat, .cmd, .csv, .txt, .js, .json, .ini, .log, .exe, .cob 等)
  if token:match("%.[%w_%-]+$") then
    return true
  end
  -- 包含路径分隔符 (/ 或 \)
  if token:find("[/\\]") then
    return true
  end
  -- Windows 绝对路径 C:\...
  if token:match("^[A-Za-z]:[/\\]") then
    return true
  end
  return false
end

--- 从原始 token 中提取纯文件名（basename）
local function extract_filename_from_token(token)
  if not token or token == "" then return "" end
  local clean = token:gsub("^[\"']", ""):gsub("[\"']$", "")
  clean = clean:gsub("^%%~[a-zA-Z]*%d*", "")
  clean = clean:gsub("^[A-Za-z]:[/\\]*", "")
  clean = clean:gsub("\\", "/")
  local fname = vim.fs.basename(clean)
  return (fname and fname ~= "") and fname or clean
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

  -- 2. 检查光标处的带百分号环境变量：%VAR%
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

  -- 5. 检查光标处是否位于文件引用或路径上（例如 night-batch.conf、%~dp0load-config.bat、C:\ops\night-batch.conf）
  local path_token = extract_path_token_at_col(line, col)
  if path_token and path_token ~= "" and is_file_token(path_token) then
    local fname = extract_filename_from_token(path_token)
    return {
      type = "file",
      raw = path_token,
      name = fname,
    }
  end

  -- 6. 回退到当前列单词并判断是否为已知变量或标识符
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

--- 解析并生成变量的穿透预览数据（严格按照简洁三行头部格式 + 代码透视）
function M.resolve_variable_peek(bufnr, var_name)
  local buf_path = vim.api.nvim_buf_get_name(bufnr)
  local buf_dir = buf_path ~= "" and vim.fs.dirname(buf_path) or vim.fn.getcwd()
  local project_root = get_project_root(buf_dir)

  local var_lower = var_name:lower()
  local display_lines = {}
  local target_filetype = "dosbatch"
  local target_file_path = nil

  -- 当前光标所在的行号（用于标注调用位置）
  local cursor_line_num = 1
  if bufnr == vim.api.nvim_get_current_buf() then
    cursor_line_num = vim.api.nvim_win_get_cursor(0)[1]
  end

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

  -- 2. 搜索配置文件中的条目（支持跨盘符与多路径查找）
  local conf_paths = find_conf_files(bufnr, buf_dir, project_root)
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

  -- 3. 确定原始值与对应的来源赋值
  local raw_value = nil
  local active_assignment = nil
  if conf_entry then
    raw_value = conf_entry.raw_value
  elseif #script_assignments > 0 then
    -- 寻找最符合上下文的赋值（优先考虑当前光标所在行之前最近的有效赋值）
    for _, sa in ipairs(script_assignments) do
      if sa.line <= cursor_line_num then
        active_assignment = sa
      end
    end
    -- 若当前位置选中的是参数占位符（如 %~2），或者光标在最前面，优先回退到具备具体初值的赋值
    if not active_assignment or active_assignment.val:match("^%%~?%d+$") then
      for _, sa in ipairs(script_assignments) do
        if not sa.val:match("^%%~?%d+$") then
          active_assignment = sa
          break
        end
      end
    end
    active_assignment = active_assignment or script_assignments[#script_assignments]
    raw_value = active_assignment and active_assignment.val or nil
  end

  -- 4. 尝试智能解析跨盘符与本地候选目标文件
  local resolved_file = nil
  if raw_value then
    resolved_file, _ = resolve_candidate_file(raw_value, buf_dir, project_root)
  end

  -- 5. 按照用户指定的结构化 3 行格式组织头部：
  -- 第一行：显示环境变量
  table.insert(display_lines, string.format("REM 变量: %%%s%%", var_name))

  -- 第二行：显示调用/定义该环境变量的路径与位置
  local source_str = ""
  local rel_buf_path = buf_path ~= "" and buf_path:gsub("^" .. vim.pesc(project_root) .. "/?", "") or "当前脚本"
  if conf_entry then
    local rel_conf = conf_entry.conf_path:gsub("^" .. vim.pesc(project_root) .. "/?", "")
    source_str = string.format("REM 来源: %s:%d (于 %s:%d 调用)", rel_conf, conf_entry.line, rel_buf_path, cursor_line_num)
  elseif active_assignment then
    source_str = string.format("REM 来源: %s:%d (%s)", rel_buf_path, active_assignment.line, active_assignment.expr)
  else
    source_str = string.format("REM 来源: %s:%d (脚本调用处)", rel_buf_path, cursor_line_num)
  end
  table.insert(display_lines, source_str)

  -- 第三行：显示该环境变量的具体值
  local val_str = ""
  if raw_value and raw_value ~= "" then
    if resolved_file then
      local rel_resolved = resolved_file:gsub("^" .. vim.pesc(project_root) .. "/?", "")
      val_str = string.format("REM 取值: %s  ->  %s  (点击或按回车直达)", raw_value, rel_resolved)
    else
      val_str = string.format("REM 取值: %s", raw_value)
    end
  else
    val_str = string.format("REM 取值: [未在本地配置或脚本中找到静态赋值]")
  end
  table.insert(display_lines, val_str)

  -- 6. 如果穿透命中了具体可读文件，展示分割线并直接呈现目标代码
  if resolved_file and file_readable(resolved_file) then
    target_file_path = resolved_file
    target_filetype = detect_filetype_by_path(resolved_file)
    table.insert(display_lines, string.format("REM ──────────────────────────────────────────────────────────"))

    local target_lines = vim.fn.readfile(resolved_file, "", 35)
    for _, tl in ipairs(target_lines) do
      table.insert(display_lines, tl)
    end
  end

  return {
    lines = display_lines,
    filetype = target_filetype,
    target_file = target_file_path,
    target_line = 1,
  }
end

--- 解析并生成标签（Subroutine）的穿透预览数据（统一三行头部结构）
function M.resolve_label_peek(bufnr, label_name)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local parsed = parser.parse(lines)
  local label_item = parsed.labels[label_name:lower()]

  if not label_item then
    return nil
  end

  local buf_path = vim.api.nvim_buf_get_name(bufnr)
  local buf_dir = buf_path ~= "" and vim.fs.dirname(buf_path) or vim.fn.getcwd()
  local project_root = get_project_root(buf_dir)
  local rel_buf_path = buf_path ~= "" and buf_path:gsub("^" .. vim.pesc(project_root) .. "/?", "") or "当前脚本"

  local start_line = label_item.line
  local preview_lines = {}

  -- 统一三行头部
  table.insert(preview_lines, string.format("REM 标签: :%s", label_item.name))
  table.insert(preview_lines, string.format("REM 来源: %s:%d", rel_buf_path, start_line))
  table.insert(preview_lines, string.format("REM 说明: 子程序定义代码段 (点击或按回车直达)"))
  table.insert(preview_lines, string.format("REM ──────────────────────────────────────────────────────────"))

  local max_lines = 30
  for i = start_line, math.min(#lines, start_line + max_lines) do
    local l = lines[i]
    if i > start_line and l:match("^%s*:[^:]") then
      break
    end
    table.insert(preview_lines, l)
  end

  return {
    lines = preview_lines,
    filetype = "dosbatch",
    target_line = start_line,
  }
end

--- 解析并生成文件引用的穿透预览数据（严格三行头部规范 + 源码透视 + 直达跳转）
function M.resolve_file_peek(bufnr, file_target)
  local buf_path = vim.api.nvim_buf_get_name(bufnr)
  local buf_dir = buf_path ~= "" and vim.fs.dirname(buf_path) or vim.fn.getcwd()
  local project_root = get_project_root(buf_dir)

  local raw_target = type(file_target) == "table" and (file_target.raw or file_target.name) or file_target
  local filename = type(file_target) == "table" and file_target.name or vim.fs.basename(raw_target)

  local cursor_line_num = 1
  if bufnr == vim.api.nvim_get_current_buf() then
    cursor_line_num = vim.api.nvim_win_get_cursor(0)[1]
  end

  local rel_buf_path = buf_path ~= "" and buf_path:gsub("^" .. vim.pesc(project_root) .. "/?", "") or "当前脚本"

  -- 尝试解析本地工程候选文件
  local resolved_file, _ = resolve_candidate_file(raw_target, buf_dir, project_root)
  if not resolved_file and filename and filename ~= raw_target then
    resolved_file, _ = resolve_candidate_file(filename, buf_dir, project_root)
  end

  local display_lines = {}
  local target_filetype = resolved_file and detect_filetype_by_path(resolved_file) or detect_filetype_by_path(filename or "")

  -- 第一行：显示目标文件（含原始引用）
  if raw_target and raw_target ~= filename then
    table.insert(display_lines, string.format("REM 文件: %s (引用: %s)", filename, raw_target))
  else
    table.insert(display_lines, string.format("REM 文件: %s", filename or raw_target))
  end

  -- 第二行：显示来源位置
  table.insert(display_lines, string.format("REM 来源: %s:%d (脚本引用处)", rel_buf_path, cursor_line_num))

  -- 第三行：显示解析出的本地路径与直达提示
  if resolved_file and file_readable(resolved_file) then
    local rel_resolved = resolved_file:gsub("^" .. vim.pesc(project_root) .. "/?", "")
    table.insert(display_lines, string.format("REM 路径: %s  (点击浮窗或按回车直达)", rel_resolved))
    table.insert(display_lines, string.format("REM ──────────────────────────────────────────────────────────"))

    local target_lines = vim.fn.readfile(resolved_file, "", 40)
    for _, tl in ipairs(target_lines) do
      table.insert(display_lines, tl)
    end
  else
    table.insert(display_lines, string.format("REM 路径: [未在工程候选路径中找到本地对应文件: %s]", filename or raw_target))
  end

  return {
    lines = display_lines,
    filetype = target_filetype,
    target_file = resolved_file,
    target_line = 1,
  }
end

--- 打开完全不透明的现代浮动窗口（无边框标题，极简外观，支持鼠标点击与键盘直达跳转）
local function open_float_window(peek_data)
  if not peek_data or not peek_data.lines or #peek_data.lines == 0 then
    vim.notify("Batch: 未找到可预览的穿透内容", vim.log.levels.INFO)
    return nil
  end

  local origin_win = vim.api.nvim_get_current_win()
  local origin_buf = vim.api.nvim_get_current_buf()

  local lines = peek_data.lines
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
  local width = math.min(110, math.max(48, max_line_len + 4))
  local height = math.min(26, math.max(3, #lines))

  -- 简洁圆角浮窗，不显示顶部标题
  local win_opts = {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
  }

  -- 边界检查：若光标下方空间不足，则向上弹出
  local win_height = vim.api.nvim_win_get_height(origin_win)
  local cursor_win_row = vim.fn.winline()
  if cursor_win_row + height + 2 > win_height and cursor_win_row > height + 2 then
    win_opts.row = -(height + 2)
  end

  -- 3. 打开原生浮动窗口，设置 100% 实体背景防穿光
  local win = vim.api.nvim_open_win(buf, false, win_opts)
  vim.wo[win].winblend = 0 -- 100% 不透明实底
  vim.wo[win].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true

  M._active_win = win
  M._active_buf = buf

  -- 4. 注册跳转与自动销毁机制
  local is_closed = false
  local function close_window()
    if is_closed then return end
    is_closed = true
    M._active_win = nil
    M._active_buf = nil
    if vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end

  local function jump_to_target(clicked_line)
    if peek_data.target_file and file_readable(peek_data.target_file) then
      local target_file = peek_data.target_file
      local line_num = peek_data.target_line or 1
      if clicked_line and clicked_line >= 5 then
        line_num = clicked_line - 4
      end
      close_window()
      vim.cmd("edit " .. vim.fn.fnameescape(target_file))
      pcall(vim.api.nvim_win_set_cursor, 0, { math.max(1, line_num), 0 })
    elseif peek_data.target_line and peek_data.target_line > 0 then
      local line_num = peek_data.target_line
      close_window()
      pcall(vim.api.nvim_win_set_cursor, origin_win, { line_num, 0 })
    else
      close_window()
    end
  end

  -- 鼠标点击浮窗直接跳转打开文件
  local function on_mouse_click()
    local mpos = vim.fn.getmousepos()
    local clicked_line = (mpos and mpos.winid == win) and mpos.line or nil
    vim.schedule(function()
      jump_to_target(clicked_line)
    end)
  end

  vim.keymap.set({ "n", "v" }, "<LeftMouse>", on_mouse_click, { buffer = buf, silent = true })
  vim.keymap.set({ "n", "v" }, "<2-LeftMouse>", on_mouse_click, { buffer = buf, silent = true })

  -- 键盘回车、gd、o 跳转打开文件
  vim.keymap.set("n", "<CR>", function()
    local cursor_row = vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_cursor(win)[1] or 1
    jump_to_target(cursor_row)
  end, { buffer = buf, silent = true, desc = "打开穿透目标文件" })

  vim.keymap.set("n", "gd", function()
    local cursor_row = vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_cursor(win)[1] or 1
    jump_to_target(cursor_row)
  end, { buffer = buf, silent = true, desc = "打开穿透目标文件" })

  vim.keymap.set("n", "o", function()
    local cursor_row = vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_cursor(win)[1] or 1
    jump_to_target(cursor_row)
  end, { buffer = buf, silent = true, desc = "打开穿透目标文件" })

  -- 浮窗内按 q 或 <Esc> 关闭
  vim.keymap.set("n", "q", close_window, { buffer = buf, silent = true, nowait = true })
  vim.keymap.set("n", "<Esc>", close_window, { buffer = buf, silent = true, nowait = true })

  -- 自动关闭机制：
  local augroup = vim.api.nvim_create_augroup("BatchPeekAutoClose_" .. win, { clear = true })

  -- 主窗口光标移动时关闭（仅在用户仍停留在原始窗口内移动时生效）
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = augroup,
    buffer = origin_buf,
    callback = function()
      local cur_win = vim.api.nvim_get_current_win()
      if cur_win == origin_win then
        close_window()
      end
    end,
  })

  -- 原始窗口失焦时，如果不是进入浮窗，则安全关闭
  vim.api.nvim_create_autocmd({ "WinLeave" }, {
    group = augroup,
    buffer = origin_buf,
    callback = function()
      vim.schedule(function()
        if is_closed or not vim.api.nvim_win_is_valid(win) then return end
        local cur_win = vim.api.nvim_get_current_win()
        if cur_win ~= win and cur_win ~= origin_win then
          close_window()
        end
      end)
    end,
  })

  -- 浮窗自身失焦时（例如用户在浮窗内切出到外部窗口），安全关闭
  vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
    group = augroup,
    buffer = buf,
    callback = function()
      vim.schedule(function()
        close_window()
      end)
    end,
  })

  return win
end

--- 预览穿透主入口函数
function M.peek(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- 如果浮窗已开启，再次按 K 直接聚焦进入浮窗
  if M._active_win and vim.api.nvim_win_is_valid(M._active_win) then
    vim.api.nvim_set_current_win(M._active_win)
    return M._active_win
  end

  local line = vim.api.nvim_get_current_line()
  local col = vim.fn.col(".")

  local target = M.extract_target_under_cursor(line, col)
  if not target then
    vim.notify("Batch: 光标处未检测到环境变量、文件或标签", vim.log.levels.INFO)
    return nil
  end

  local peek_data = nil
  if target.type == "variable" then
    peek_data = M.resolve_variable_peek(bufnr, target.name)
  elseif target.type == "label" then
    peek_data = M.resolve_label_peek(bufnr, target.name)
  elseif target.type == "file" then
    peek_data = M.resolve_file_peek(bufnr, target)
  end

  if not peek_data then
    vim.notify("Batch: 无法解析 " .. tostring(target.name or target.raw) .. " 的穿透信息", vim.log.levels.WARN)
    return nil
  end

  return open_float_window(peek_data)
end

return M
