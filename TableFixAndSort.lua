local lfs = require("lfs")

local defaultTargetTable = "GreatVaultOddsDB"

local config = {
  scriptFileName = "TableFixAndSort.lua",
  targetTableName = (arg and arg[1]) or defaultTargetTable,

  inputDir = "Input",
  archivedInputDir = "Input/Archived Inputs",
  sortedOutputDir = "Sorted Tables",

  sortRules = {
    scalarKeys = 1,
    prioritisedTableKeys = 2,
    otherTableKeys = 3,

    prioritisedTableKeyOrder = {
      sources = 1,
    },
  },
}

local Sorter = {
  config = config,
}

local function joinPath(...)
  return table.concat({...}, "/")
end

local function filenameFromPath(path)
  return path:match("[^/\\]+$") or path
end

local function escapePattern(text)
  return text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
end

local function isLuaFile(filename)
  return filename:match("%.lua$") ~= nil
end

local function readFile(path)
  local file, err = io.open(path, "rb")
  if not file then
    error(("Failed to read %s: %s"):format(path, tostring(err)))
  end

  local content = file:read("*a")
  file:close()
  return content
end

local function writeFile(path, content)
  local file, err = io.open(path, "wb")
  if not file then
    error(("Failed to write %s: %s"):format(path, tostring(err)))
  end

  file:write(content)
  file:close()
end

local function copyFile(src, dest)
  writeFile(dest, readFile(src))
end

local function removeFile(path)
  local ok, err = os.remove(path)
  if not ok then
    print(("[WARN] Failed to remove %s: %s"):format(path, tostring(err)))
  end
  return ok
end

local function ensureDirectory(path)
  local attr = lfs.attributes(path)
  if not attr then
    local ok, err = lfs.mkdir(path)
    if not ok then
      error(("Failed to create directory %s: %s"):format(path, tostring(err)))
    end
    return
  end

  if attr.mode ~= "directory" then
    error(path .. " exists but is not a directory")
  end
end

local function resolveFilenameCollision(dir, filename)
  local name, ext = filename:match("^(.-)(%..-)$")
  if not name then
    name, ext = filename, ""
  end

  local candidate = filename
  local counter = 1

  while lfs.attributes(joinPath(dir, candidate)) do
    candidate = ("%s_%d%s"):format(name, counter, ext)
    counter = counter + 1
  end

  return candidate
end

local function archiveFile(src, destDir)
  local filename = filenameFromPath(src)
  local archivedName = resolveFilenameCollision(destDir, filename)
  local archivedPath = joinPath(destDir, archivedName)

  copyFile(src, archivedPath)
  return archivedPath
end

local function logInfo(...)
  print("[INFO]", ...)
end

local function logError(file, message)
  print(("[ERROR] %s: %s"):format(file or "<unknown>", tostring(message)))
end

local function prepareSavedVariableSource(source, tableName)
  source = source:gsub("\r\n", "\n"):gsub("\r", "\n")
  if source:sub(-1) ~= "\n" then
    source = source .. "\n"
  end

  local tablePattern = escapePattern(tableName)
  local declarationPattern = "^%s*" .. tablePattern .. "%s*=%s*{"
  local localDeclarationPattern = "^%s*local%s+" .. tablePattern .. "%s*=%s*{"
  -- The frontier prevents `return GreatVaultOddsDBExtra` from matching this table.
  -- http://lua-users.org/wiki/FrontierPattern
  local returnPattern = "^%s*return%s+" .. tablePattern .. "%f[^_%w]"

  local lines = {}
  local foundTable = false
  local hasLocal = false
  local hasReturn = false

  for line in source:gmatch("([^\n]*)\n") do
    if not foundTable then
      if line:match(localDeclarationPattern) then
        foundTable = true
        hasLocal = true
      elseif line:match(declarationPattern) then
        foundTable = true
      end
    end

    if line:match(returnPattern) then
      hasReturn = true
    end

    table.insert(lines, line)
  end

  if not foundTable then
    return nil, "target table not found"
  end

  if not hasLocal then
    for i, line in ipairs(lines) do
      if line:match(declarationPattern) then
        lines[i] = line:gsub("^(%s*)(" .. tablePattern .. "%s*=%s*{)", "%1local %2", 1)
        break
      end
    end
  end

  if not hasReturn then
    table.insert(lines, "")
    table.insert(lines, "return " .. tableName)
  end

  return table.concat(lines, "\n")
end

local function loadTableFromSource(source, chunkName)
  local chunk, err = load(source, "@" .. chunkName)
  if not chunk then
    error(err)
  end

  local ok, result = pcall(chunk)
  if not ok then
    error(result)
  end

  if type(result) ~= "table" then
    error("returned value is not a table")
  end

  return result
end

local function keySortBucket(tbl, key, sortRules)
  if type(tbl[key]) ~= "table" then
    return sortRules.scalarKeys
  end

  if type(key) == "string" and sortRules.prioritisedTableKeyOrder[key] then
    return sortRules.prioritisedTableKeys, sortRules.prioritisedTableKeyOrder[key]
  end

  return sortRules.otherTableKeys
end

local function compareKeys(tbl, sortRules, a, b)
  local aBucket, aPriority = keySortBucket(tbl, a, sortRules)
  local bBucket, bPriority = keySortBucket(tbl, b, sortRules)

  if aBucket ~= bBucket then
    return aBucket < bBucket
  end

  if aPriority and bPriority and aPriority ~= bPriority then
    return aPriority < bPriority
  end

  if type(a) == "number" and type(b) == "number" then
    return a < b
  end

  if type(a) == "string" and type(b) == "string" then
    return a < b
  end

  return tostring(a) < tostring(b)
end

local function sortedKeys(tbl, sortRules)
  local keys = {}
  for key in pairs(tbl) do
    table.insert(keys, key)
  end

  table.sort(keys, function(a, b)
    return compareKeys(tbl, sortRules, a, b)
  end)

  return keys
end

local function formatKey(key)
  if type(key) == "string" and key:match("^[_%a][_%w]*$") then
    return key
  end

  if type(key) == "string" then
    return "[" .. string.format("%q", key) .. "]"
  end

  return "[" .. tostring(key) .. "]"
end

local function serialiseValue(value, indent, sortRules)
  if type(value) == "table" then
    return Sorter.serialiseTable(value, indent, sortRules)
  end

  if type(value) == "string" then
    return string.format("%q", value)
  end

  return tostring(value)
end

function Sorter.serialiseTable(tbl, indent, sortRules)
  indent = indent or ""
  sortRules = sortRules or config.sortRules

  local nextIndent = indent .. "    "
  local parts = {"{\n"}

  for _, key in ipairs(sortedKeys(tbl, sortRules)) do
    local value = serialiseValue(tbl[key], nextIndent, sortRules)
    table.insert(parts, nextIndent .. formatKey(key) .. " = " .. value .. ",\n")
  end

  table.insert(parts, indent .. "}")
  return table.concat(parts)
end

local function outputPathFor(filename)
  local baseOutputName = filename:gsub("%.lua$", ".txt")
  local outputName = resolveFilenameCollision(config.sortedOutputDir, baseOutputName)
  return joinPath(config.sortedOutputDir, outputName)
end

local function processFile(filename)
  local inputPath = joinPath(config.inputDir, filename)
  local source = readFile(inputPath)
  local loadableSource, prepareErr = prepareSavedVariableSource(source, config.targetTableName)

  if not loadableSource then
    return {
      status = "skipped",
      file = filename,
      inputPath = inputPath,
      reason = prepareErr,
    }
  end

  local ok, loadedTable = pcall(loadTableFromSource, loadableSource, inputPath)
  if not ok then
    return {
      status = "failed",
      file = filename,
      inputPath = inputPath,
      step = "load",
      error = loadedTable,
    }
  end

  local archiveOk, archivedPath = pcall(archiveFile, inputPath, config.archivedInputDir)
  if not archiveOk then
    return {
      status = "failed",
      file = filename,
      inputPath = inputPath,
      step = "archive",
      error = archivedPath,
    }
  end

  local outputPath = outputPathFor(filename)
  local writeOk, writeErr = pcall(writeFile, outputPath, Sorter.serialiseTable(loadedTable))
  if not writeOk then
    return {
      status = "failed",
      file = filename,
      inputPath = inputPath,
      archivePath = archivedPath,
      step = "write",
      error = writeErr,
    }
  end

  removeFile(inputPath)

  return {
    status = "processed",
    file = filename,
    inputPath = inputPath,
    archivePath = archivedPath,
    outputPath = outputPath,
  }
end

local function collectInputFiles()
  local files = {}

  for filename in lfs.dir(config.inputDir) do
    if isLuaFile(filename) and filename ~= config.scriptFileName then
      table.insert(files, filename)
    end
  end

  table.sort(files)
  return files
end

local function printSummary(results)
  local skipped = {}
  local failed = {}

  for _, result in ipairs(results) do
    if result.status == "skipped" then
      table.insert(skipped, result)
    elseif result.status == "failed" then
      table.insert(failed, result)
    end
  end

  logInfo("\n=== Processing Summary ===")

  if #skipped > 0 then
    logInfo("Skipped files (table '" .. config.targetTableName .. "' not found):")
    for _, result in ipairs(skipped) do
      print(" - " .. result.file)
    end
  else
    logInfo("No files skipped.")
  end

  if #failed > 0 then
    logInfo("\nFailed files:")
    for _, result in ipairs(failed) do
      print((" - %s: %s failed (%s)"):format(result.file, result.step, tostring(result.error)))
    end
  else
    logInfo("No files failed.")
  end

  logInfo("\nAll done.")
end

local function main()
  ensureDirectory(config.inputDir)
  ensureDirectory(config.archivedInputDir)
  ensureDirectory(config.sortedOutputDir)

  local results = {}

  for _, filename in ipairs(collectInputFiles()) do
    logInfo("Processing:", filename)

    local result = processFile(filename)
    table.insert(results, result)

    if result.status == "processed" then
      logInfo("Archived original as:", result.archivePath)
      logInfo("Sorted table written to:", result.outputPath)
    elseif result.status == "failed" then
      logError(filename, result.step .. " failed: " .. tostring(result.error))
    end
  end

  printSummary(results)
end

Sorter.prepareSavedVariableSource = prepareSavedVariableSource
Sorter.loadTableFromSource = loadTableFromSource
Sorter.sortedKeys = sortedKeys
Sorter.formatKey = formatKey
Sorter.processFile = processFile
Sorter.main = main

if arg and filenameFromPath(arg[0] or "") == config.scriptFileName then
  main()
else
  return Sorter
end
