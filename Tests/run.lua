package.path = "./?.lua;" .. package.path

local sorter = require("TableFixAndSort")

local function readFile(path)
  local file, err = io.open(path, "rb")
  if not file then
    error(("Failed to read %s: %s"):format(path, tostring(err)))
  end

  local content = file:read("*a")
  file:close()
  return content
end

local function assertEqual(generatedOutput, knownGoodOutput, message)
  knownGoodOutput = knownGoodOutput:gsub("\r\n", "\n"):gsub("\n$", "")
  generatedOutput = generatedOutput:gsub("\r\n", "\n")

  if generatedOutput ~= knownGoodOutput then
    error(("%s\nKnown good output:\n%s\nGenerated output:\n%s"):format(
      message,
      knownGoodOutput,
      generatedOutput
    ), 2)
  end
end

local function testFixture(name)
  local inputPath = "Tests/Fixtures/Inputs/" .. name .. ".lua"
  local knownGoodPath = "Tests/Fixtures/ExpectedOutputs/" .. name .. ".txt"

  local source = readFile(inputPath)
  local loadableSource = assert(sorter.prepareSavedVariableSource(source, "GreatVaultOddsDB"))
  local tbl = sorter.loadTableFromSource(loadableSource, inputPath)
  local generatedOutput = sorter.serialiseTable(tbl)
  local knownGoodOutput = readFile(knownGoodPath)

  assertEqual(generatedOutput, knownGoodOutput, "Fixture failed: " .. name)
end

local function testPrepareSavedVariableSource()
  local source = "GreatVaultOddsDB = {\n}\n"
  local generatedOutput = assert(sorter.prepareSavedVariableSource(source, "GreatVaultOddsDB"))
  local knownGoodOutput = "local GreatVaultOddsDB = {\n}\n\nreturn GreatVaultOddsDB"

  assertEqual(generatedOutput, knownGoodOutput, "prepareSavedVariableSource should add local and return")
end

local function testFormatKey()
  assertEqual(sorter.formatKey("sources"), "sources", "identifier keys should not be bracketed")
  assertEqual(sorter.formatKey("item-level"), "[\"item-level\"]", "non-identifier string keys should be quoted")
  assertEqual(sorter.formatKey(42), "[42]", "numeric keys should be bracketed")
end

local function testExistingReturnWithComment()
  local source = "local GreatVaultOddsDB = {\n}\n\nreturn GreatVaultOddsDB -- already loadable\n"
  local generatedOutput = assert(sorter.prepareSavedVariableSource(source, "GreatVaultOddsDB"))
  local knownGoodOutput = "local GreatVaultOddsDB = {\n}\n\nreturn GreatVaultOddsDB -- already loadable"

  assertEqual(generatedOutput, knownGoodOutput, "prepareSavedVariableSource should keep an existing return with a comment")
end

local fixtures = {
  "basic",
  "Midnight_M0",
  "Midnight_S1_ID-105",
  "Midnight_S1",
}

for _, fixture in ipairs(fixtures) do
  testFixture(fixture)
end

testPrepareSavedVariableSource()
testFormatKey()
testExistingReturnWithComment()

print("All tests passed.")
