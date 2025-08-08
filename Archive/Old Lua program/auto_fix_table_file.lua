-- auto_fix_table_file.lua
-- Usage: lua auto_fix_table_file.lua InputTable1.lua

local function transform_file(path)
  local input = io.open(path, "r")
  if not input then
    error("Failed to open file: " .. path)
  end

  local lines = {}
  local tableName = nil

  for line in input:lines() do
    if not tableName then
      -- Look for the first assignment line: GreatVaultOddsDB = {
      tableName = line:match("^%s*(%w+)%s*=%s*{")
      if tableName then
        -- Prepend "local "
        table.insert(lines, "local " .. line)
      else
        table.insert(lines, line)
      end
    else
      table.insert(lines, line)
    end
  end
  input:close()

  if not tableName then
    error("Could not find a table declaration in " .. path)
  end

  -- Add a return statement at the bottom
  table.insert(lines, "")
  table.insert(lines, "return " .. tableName)

  -- Overwrite the original file (or write to a new one)
  local output = io.open(path, "w")
  for _, l in ipairs(lines) do
    output:write(l .. "\n")
  end
  output:close()

  print("Transformed file: " .. path .. " (added 'local' and 'return " .. tableName .. "')")
end

-- Main
local filePath = arg[1]
if not filePath then
  print("Usage: lua auto_fix_table_file.lua <path-to-lua-file>")
else
  transform_file(filePath)
end

-- auto_fix_table_file.lua

local lfs = require("lfs")  -- LuaFileSystem, optional if you prefer pure shell call

local function transform_file(path)
  local input = io.open(path, "r")
  if not input then
    print("Failed to open: " .. path)
    return
  end

  local lines = {}
  local tableName = nil

  for line in input:lines() do
    if not tableName then
      tableName = line:match("^%s*(%w+)%s*=%s*{")
      if tableName then
        table.insert(lines, "local " .. line)
      else
        table.insert(lines, line)
      end
    else
      table.insert(lines, line)
    end
  end
  input:close()

  if not tableName then
    print("No table assignment found in " .. path)
    return
  end

  table.insert(lines, "")
  table.insert(lines, "return " .. tableName)

  local output = io.open(path, "w")
  for _, l in ipairs(lines) do
    output:write(l .. "\n")
  end
  output:close()

  print("✔ Transformed: " .. path)
end

-- Get the filename of this script so we can exclude it
local function get_script_name()
  local full_path = arg[0]
  return full_path:match("^.+/(.+)$") or full_path:match("^.+\\(.+)$") or full_path
end

-- Main logic
local function main()
  local targetFile = arg[1]

  if targetFile then
    transform_file(targetFile)
    return
  end

  local thisFile = get_script_name()

  -- Pure Lua solution using io.popen to list directory
  local p = io.popen("ls *.lua 2> /dev/null") or io.popen("dir /b *.lua 2> nul")
  if not p then
    print("Could not list Lua files.")
    return
  end

  for file in p:lines() do
    if file ~= thisFile then
      transform_file(file)
    end
  end
  p:close()
end

main()
