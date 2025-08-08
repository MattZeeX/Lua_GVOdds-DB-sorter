-- TableFixAndSort.lua

--[[
  This script processes Lua files containing a specific table (default: GreatVaultOddsDB).
  It does the following for each .lua file found in the 'Input' folder:

    1. Copies the original unaltered Lua file to 'Input/Archived Inputs',
       unless the file is skipped or processing fails.
       - If a file with the same name already exists, appends a numeric suffix (_1, _2, etc.).
    2. Ensures the specified table is declared with 'local' and ends with 'return <table>'.
       - These modifications are done on a temporary working file.
    3. Loads the table, sorts its keys, and writes a .txt representation of the table
       into the 'Sorted Tables' directory.
       - Again, ensures no name collisions by adding a numeric suffix when needed.

  Configuration:
    - You can optionally pass a table name as a command line argument.
    - By default, the table name is 'GreatVaultOddsDB'.
]]

local lfs = require("lfs")

-- === Configuration ===
local scriptFileName = "TableFixAndSort.lua"
local defaultTargetTable = "GreatVaultOddsDB"
local cliArgTargetTable = arg and arg[1] or nil
local targetTableName = cliArgTargetTable or defaultTargetTable

-- Directory paths
local inputDir = "Input"
local archivedInputDir = inputDir .. "/Archived Inputs"
local sortedOutputDir = "Sorted Tables"

-- Get the filename this script is running from
local actualScriptPath = arg and arg[0] or scriptFileName
local actualScriptName = actualScriptPath:match("[^/\\]+$") or scriptFileName

-- === Directory Setup ===
local function ensureDirectory(path)
  local attr = lfs.attributes(path)
  if not attr then
    local ok, err = lfs.mkdir(path)
    if not ok then error("Failed to create directory '" .. path .. "': " .. tostring(err)) end
  elseif attr.mode ~= "directory" then
    error("'" .. path .. "' exists but is not a directory.")
  end
end

-- === File Operations ===
local function copyFile(src, dest)
  local inFile = io.open(src, "rb")
  if not inFile then error("Failed to open " .. src) end
  local content = inFile:read("*a")
  inFile:close()

  local outFile = io.open(dest, "wb")
  if not outFile then error("Failed to open " .. dest .. " for writing") end
  outFile:write(content)
  outFile:close()
end

-- Resolves a filename collision by appending _1, _2, etc.
local function resolveFilenameCollision(basePath, filename)
  local name, ext = filename:match("^(.-)(%..-)$")
  if not name then name, ext = filename, "" end
  local counter = 1
  local candidate = filename
  while lfs.attributes(basePath .. "/" .. candidate) do
    candidate = string.format("%s_%d%s", name, counter, ext)
    counter = counter + 1
  end
  return candidate
end

-- === Table Fixing and Serialization ===
local function fixTableFile(filePath, tableName)
  local input = io.open(filePath, "r")
  if not input then error("Failed to open " .. filePath) end

  local lines = {}
  local foundTable = false
  local hasLocal = false
  local hasReturn = false

  for line in input:lines() do
    if not foundTable then
      local tn = line:match("^%s*local%s+" .. tableName .. "%s*=%s*{")
      if tn then
        foundTable = true
        hasLocal = true
      elseif line:match("^%s*" .. tableName .. "%s*=%s*{") then
        foundTable = true
      end
    end

    if line:match("^%s*return%s+" .. tableName) then
      hasReturn = true
    end

    table.insert(lines, line)
  end
  input:close()

  if not foundTable then
    return false, "Target table '" .. tableName .. "' not found."
  end

  if not hasLocal then
    for i, line in ipairs(lines) do
      if line:match("^%s*" .. tableName .. "%s*=%s*{") then
        lines[i] = line:gsub("^%s*(" .. tableName .. "%s*=%s*{)", "local %1")
        break
      end
    end
  end

  if not hasReturn then
    table.insert(lines, "")
    table.insert(lines, "return " .. tableName)
  end

  local output = io.open(filePath, "w")
  for _, line in ipairs(lines) do
    output:write(line, "\n")
  end
  output:close()

  return true
end

local function loadTableFromFile(filePath)
  local f, err = loadfile(filePath)
  if not f then error("Failed to load " .. filePath .. ": " .. err) end
  local success, tbl = pcall(f)
  if not success then error("Execution failed: " .. tbl) end
  if type(tbl) ~= "table" then error("Returned value is not a table") end
  return tbl
end

local function serializeTable(tbl, indent)
  indent = indent or ""
  local nextIndent = indent .. "  "
  local keys = {}

  for k in pairs(tbl) do table.insert(keys, k) end

  table.sort(keys, function(a, b)
    if type(a) == "number" and type(b) == "number" then return a < b
    elseif type(a) == "string" and type(b) == "string" then return a < b
    else return tostring(a) < tostring(b) end
  end)

  local parts = {"{\n"}

  for _, k in ipairs(keys) do
    local v = tbl[k]
    local keyRepr = (type(k) == "string" and k:match("^[_%a][_%w]*$") and k) or
                    ("[" .. (type(k) == "string" and string.format("%q", k) or tostring(k)) .. "]")

    local valRepr
    if type(v) == "table" then
      valRepr = serializeTable(v, nextIndent)
    elseif type(v) == "string" then
      valRepr = string.format("%q", v)
    else
      valRepr = tostring(v)
    end

    table.insert(parts, nextIndent .. keyRepr .. " = " .. valRepr .. ",\n")
  end

  table.insert(parts, indent .. "}")
  return table.concat(parts)
end

local function writeSortedTableToTxt(tbl, filePath)
  local file = io.open(filePath, "w")
  if not file then error("Failed to open " .. filePath .. " for writing") end
  file:write(serializeTable(tbl))
  file:close()
end

-- === Main Loop ===
local function processLuaFiles()
  -- Ensure required directories exist or create them
  ensureDirectory(inputDir)
  ensureDirectory(archivedInputDir)
  ensureDirectory(sortedOutputDir)

  -- Tables to track files that failed or were skipped
  local failedFiles = {}
  local skippedFiles = {}

  -- Iterate through all files in the input directory
  for file in lfs.dir(inputDir) do
    if file:match("%.lua$") then
      local fullInputPath = inputDir .. "/" .. file
      print("\nProcessing:", file)

      -- Temporary working copy path inside input folder
      local tempPath = inputDir .. "/__working__.lua"
      copyFile(fullInputPath, tempPath)

      -- Try fixing the table file on the temporary copy
      local ok, msg = pcall(fixTableFile, tempPath, targetTableName)
      if not ok then
        -- fixTableFile threw an error, record failure, remove temp copy, do NOT archive original
        print("Error fixing table:", msg)
        table.insert(failedFiles, { file = file, reason = msg })
        os.remove(tempPath)
      elseif not msg then
        -- fixTableFile returned false => target table not found, skip processing
        print("Skipping file (target table not found):", file)
        table.insert(skippedFiles, file)
        os.remove(tempPath) -- Clean up temp file
        -- Do NOT archive the original, leave it in input folder
      else
        -- fixTableFile succeeded; load the fixed table from the temporary file first
        local tbl
        local loadSuccess, loadResult = pcall(loadTableFromFile, tempPath)
        if not loadSuccess then
          -- Loading failed, record failure, remove temp file; do not archive
          print("Failed to load/execute table:", loadResult)
          table.insert(failedFiles, { file = file, reason = loadResult })
          os.remove(tempPath)
        else
          tbl = loadResult

          -- Now archive the original input file
          local resolvedArchiveName = resolveFilenameCollision(archivedInputDir, file)
          local archivedCopyPath = archivedInputDir .. "/" .. resolvedArchiveName

          local archiveOk, archiveErr = pcall(copyFile, fullInputPath, archivedCopyPath)
          if not archiveOk then
            -- Archiving failed, treat as failure and keep original input untouched
            print("Error archiving original file:", archiveErr)
            table.insert(failedFiles, { file = file, reason = "Archiving failed: " .. archiveErr })
            os.remove(tempPath)
          else
            print("Archived original as:", archivedCopyPath)

            -- Write the sorted table to output .txt file
            local baseOutputName = file:gsub("%.lua$", ".txt")
            local resolvedOutputName = resolveFilenameCollision(sortedOutputDir, baseOutputName)
            local outputTxtPath = sortedOutputDir .. "/" .. resolvedOutputName

            local okWrite, errWrite = pcall(writeSortedTableToTxt, tbl, outputTxtPath)
            if not okWrite then
              print("Failed to write sorted table:", errWrite)
              table.insert(failedFiles, { file = file, reason = "Failed to write sorted table: " .. errWrite })
              -- Keep archived original and input untouched here
            else
              print("Sorted table written to:", outputTxtPath)
              -- Since all succeeded, remove original input file to keep folder clean
              local removed = os.remove(fullInputPath)
              if removed then
                print("Removed original input file:", fullInputPath)
              else
                print("Warning: failed to remove original input file:", fullInputPath)
              end
            end

            os.remove(tempPath) -- Clean up temp working file
          end
        end
      end
    end
  end

  -- Print summary of skipped and failed files
  print("\n=== Processing Summary ===")
  if #skippedFiles > 0 then
    print("Skipped files (table '" .. targetTableName .. "' not found):")
    for _, f in ipairs(skippedFiles) do
      print(" - " .. f)
    end
  else
    print("No files skipped.")
  end

  if #failedFiles > 0 then
    print("\nFailed files:")
    for _, f in ipairs(failedFiles) do
      print(string.format(" - %s: %s", f.file, f.reason))
    end
  else
    print("No files failed.")
  end

  print("\nAll done.")
end

processLuaFiles()
