local function prompt_overwrite(filePath)
  local file = io.open(filePath, "r")
  if not file then
    return true  -- File doesn't exist; safe to write
  end

  local content = file:read("*a")
  file:close()

  if content ~= "" then
    io.write("File '" .. filePath .. "' already exists and is not empty. Overwrite? (y/n): ")
    local answer = io.read()
    return answer:lower() == "y"
  end

  return true  -- File exists but is empty; okay to overwrite
end

local function sorted_keys(tbl)
  local keys = {}
  for k in pairs(tbl) do table.insert(keys, k) end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)
  return keys
end

local function table_to_string(tbl, indent)
  indent = indent or 0
  local result = ""
  local padding = string.rep("  ", indent)
  local keys = sorted_keys(tbl)
  for _, key in ipairs(keys) do
    local value = tbl[key]
    local keyStr = (type(key) == "string") and string.format("[%q]", key) or "[" .. tostring(key) .. "]"
    if type(value) == "table" then
      result = result .. padding .. keyStr .. " = {\n" .. table_to_string(value, indent + 1) .. padding .. "},\n"
    else
      result = result .. padding .. keyStr .. " = " .. tostring(value) .. ",\n"
    end
  end
  return result
end

local function write_table_to_file(tbl, outputPath)
  if prompt_overwrite(outputPath) then
    local file = io.open(outputPath, "w")
    if file then
      file:write("{\n" .. table_to_string(tbl, 1) .. "}\n")
      file:close()
      print("Wrote sorted table to " .. outputPath)
    else
      error("Failed to open file for writing: " .. outputPath)
    end
  else
    print("Skipped writing to " .. outputPath)
  end
end

-- Main Execution
local input1 = "InputTable1.lua"
local input2 = "InputTable2.lua"
local output1 = "OutputTable1.txt"
local output2 = "OutputTable2.txt"

local status1, tbl1 = pcall(dofile, input1)
local status2, tbl2 = pcall(dofile, input2)

if not status1 or type(tbl1) ~= "table" then
  error("Failed to load or parse " .. input1)
end
if not status2 or type(tbl2) ~= "table" then
  error("Failed to load or parse " .. input2)
end

write_table_to_file(tbl1, output1)
write_table_to_file(tbl2, output2)
