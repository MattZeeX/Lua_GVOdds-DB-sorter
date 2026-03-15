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
local targetTableName = (arg and arg[1]) or defaultTargetTable
local prioritizedTableKeyOrder = {
  sources = 1,
}

-- Directory paths (relative to CMD directory)
local inputDir = "Input"
local archivedInputDir = inputDir .. "/Archived Inputs"
local sortedOutputDir = "Sorted Tables"

-- Get the filename this script is running from
local actualScriptPath = arg and arg[0] or scriptFileName
local actualScriptName = actualScriptPath:match("[^/\\]+$") or scriptFileName

local isExcludedFile = {
    ["__working__.lua"] = true,
    [scriptFileName] = true,
    [actualScriptName] = true,
}

-- === Utility Functions ===
local function isLuaFile(filename)
  return filename:match("%.lua$")
end

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
  local inFile, inErr = io.open(src, "rb")
  if not inFile then error("Failed to open " .. src .. ": " .. tostring(inErr)) end
  local content = inFile:read("*a")
  inFile:close()

  local outFile, outErr = io.open(dest, "wb")
  if not outFile then error("Failed to open " .. dest .. " for writing: " .. tostring(outErr)) end
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
  local input, inputErr = io.open(filePath, "r")
  if not input then error("Failed to open " .. filePath .. ": " .. tostring(inputErr)) end

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

  local output, outputErr = io.open(filePath, "w")
  if not output then
    error("Failed to open " .. filePath .. " for writing: " .. tostring(outputErr))
  end
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
  local nextIndent = indent .. "    "
  local keys = {}

  for k in pairs(tbl) do table.insert(keys, k) end

  local function getKeyBucket(key)
    local value = tbl[key]

    if type(value) ~= "table" then
      return 1
    end

    if type(key) == "string" then
      local metadataPriority = prioritizedTableKeyOrder[key]
      if metadataPriority then
        return 2, metadataPriority
      end
    end

    return 3
  end

  table.sort(keys, function(a, b)
    local aBucket, aPriority = getKeyBucket(a)
    local bBucket, bPriority = getKeyBucket(b)

    if aBucket ~= bBucket then
      return aBucket < bBucket
    end

    if aBucket == 2 and aPriority ~= bPriority then
      return aPriority < bPriority
    end

    if type(a) == "number" and type(b) == "number" then
      return a < b -- numeric comparison
    elseif type(a) == "string" and type(b) == "string" then
      return a < b -- alphabetical comparison
    else
      return tostring(a) < tostring(b)
    end
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
  local file, err = io.open(filePath, "w")
  if not file then error("Failed to open " .. filePath .. " for writing: " .. tostring(err)) end
  file:write(serializeTable(tbl))
  file:close()
end

-- === Logging Helpers ===

local function logInfo(...)
  print("[INFO]", ...)
end

local function logWarn(...)
  print("[WARN]", ...)
end

local function logError(file, err)
  print(string.format("[ERROR] %s: %s", file or "<unknown>", err))
end

-- === File Helpers ===

local function archiveFile(src, destDir)
  local filename = src:match("[^/\\]+$")
  local resolvedName = resolveFilenameCollision(destDir, filename)
  local destPath = destDir .. "/" .. resolvedName
  local ok, err = pcall(copyFile, src, destPath)
  return ok, err, destPath
end

local function removeFile(path)
  local ok, err = os.remove(path)
  if not ok then
    logWarn("Failed to remove file: " .. path .. " (" .. tostring(err) .. ")")
  end
  return ok
end

-- === Main File Processing Function ===

local function processFile(file)
  local inputPath = inputDir .. "/" .. file
  local tempPath = inputDir .. "/__working__.lua"       -- Temporary working copy path inside input folder

  copyFile(inputPath, tempPath)
      -- Try fixing the table file on the temporary copy
  local fixSuccess, fixResult = pcall(fixTableFile, tempPath, targetTableName)
  if not fixSuccess then
    logError(file, "Fix failed: " .. fixResult)  -- fixTableFile threw an error, record failure, remove temp copy, do NOT archive original
    removeFile(tempPath)
    return false, "fix failed"
  elseif not fixResult then -- fixTableFile returned false => target table not found, skip processing
    removeFile(tempPath)  -- Clean up temp file
        -- Do NOT archive the original, leave it in input folder
    return nil, "table not found"
  end

  -- fixTableFile succeeded; load the fixed table from the temporary file first

  local loadSuccess, loadedTable = pcall(loadTableFromFile, tempPath)
  if not loadSuccess then -- Loading failed, record failure, remove temp file; do not archive
    logError(file, "Load failed: " .. loadedTable)
    removeFile(tempPath)
    return false, "load failed"
  end

  -- Now archive the original input file
  local archiveOk, archiveErr, archivedPath = archiveFile(inputPath, archivedInputDir)
  if not archiveOk then -- Archiving failed, treat as failure and keep original input untouched
    logError(file, "Archive failed: " .. archiveErr)
    removeFile(tempPath)
    return false, "archive failed"
  end
  logInfo("Archived original as:", archivedPath)

  -- Write the sorted table to output .txt file
  local baseOutputName = file:gsub("%.lua$", ".txt")
  local resolvedOutputName = resolveFilenameCollision(sortedOutputDir, baseOutputName)
  local outputTxtPath = sortedOutputDir .. "/" .. resolvedOutputName

  local writeOk, writeErr = pcall(writeSortedTableToTxt, loadedTable, outputTxtPath)
  if not writeOk then -- Keep archived original and input untouched here
    logError(file, "Write failed: " .. writeErr)
    removeFile(tempPath)
    return false, "write failed"
  end

  -- Since all succeeded, remove original input file to keep folder clean
  logInfo("Sorted table written to:", outputTxtPath)

  removeFile(inputPath)  -- Clean original input file on success
  removeFile(tempPath)   -- Clean temp working file

  return true
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
    -- if file:match("%.lua$") and file ~= "__working__.lua" and file ~= scriptFileName and file ~= actualScriptName then
    if isLuaFile(file) and not isExcludedFile[file] then
      logInfo("Processing:", file)
      local status, reason = processFile(file)
      if status == true then
        -- Success, nothing to do here
      elseif status == false then
        table.insert(failedFiles, {file = file, reason = reason})
      elseif status == nil then
        -- skipped (target table not found)
        table.insert(skippedFiles, file)
      end
    end
  end

  -- Print summary of skipped and failed files
  logInfo("\n=== Processing Summary ===")
  if #skippedFiles > 0 then
    logInfo("Skipped files (table '" .. targetTableName .. "' not found):")
    for _, f in ipairs(skippedFiles) do
      print(" - " .. f)
    end
  else
    logInfo("No files skipped.")
  end

  if #failedFiles > 0 then
    logInfo("\nFailed files:")
    for _, f in ipairs(failedFiles) do
      print(string.format(" - %s: %s", f.file, f.reason))
    end
  else
    logInfo("No files failed.")
  end

  logInfo("\nAll done.")
end

processLuaFiles()
