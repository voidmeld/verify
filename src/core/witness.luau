--!strict

local Shape = require "./shape"

local DEFAULT_ERROR_PATTERNS: { string } = {
	"attempt to",
	"refused",
	"Infinite yield",
	"not authorized",
	"Stack Begin",
}

local DEFAULT_BLOCK_BEGIN_PATTERNS: { string } = { "Stack Begin" }

local DEFAULT_BLOCK_END_PATTERNS: { string } = { "Stack End" }

local copyStrings = Shape.copyStrings

local function containsAny(line: string, needles: { string }): boolean
	for _, needle in needles do
		if string.find(line, needle, 1, true) ~= nil then
			return true
		end
	end
	return false
end

local function optionalPatterns(value: unknown, label: string): { string }?
	if value == nil then
		return nil
	end
	return copyStrings(value, label)
end

local function optionalPredicate(value: unknown, label: string): ((line: string) -> boolean)?
	if value == nil then
		return nil
	end
	if type(value) ~= "function" then
		error(label .. " must be a function", 3)
	end
	return value :: (line: string) -> boolean
end

export type ClassifyOptions = {
	errorPatterns: { string }?,
	ignorePatterns: { string }?,
	ignore: ((line: string) -> boolean)?,
	blockBeginPatterns: { string }?,
	blockEndPatterns: { string }?,
	caseInsensitive: boolean?,
}

local function classifyConsole(lines: unknown, options: ClassifyOptions?): { string }
	local source = copyStrings(lines, "lines")
	local selected: ClassifyOptions = if options ~= nil then options else {}
	local errorPatterns = optionalPatterns(selected.errorPatterns, "errorPatterns") or DEFAULT_ERROR_PATTERNS
	local ignorePatterns = optionalPatterns(selected.ignorePatterns, "ignorePatterns") or {}
	local blockBeginPatterns = optionalPatterns(selected.blockBeginPatterns, "blockBeginPatterns")
	local blockEndPatterns = optionalPatterns(selected.blockEndPatterns, "blockEndPatterns")
	local ignore = optionalPredicate(selected.ignore, "ignore")
	if (blockBeginPatterns == nil) ~= (blockEndPatterns == nil) then
		error("blockBeginPatterns and blockEndPatterns must be supplied together", 2)
	end

	local caseInsensitive = selected.caseInsensitive == true
	local function fold(text: string): string
		return if caseInsensitive then string.lower(text) else text
	end

	local function matches(line: string, needles: { string }): boolean
		return containsAny(fold(line), needles)
	end

	local function ignored(line: string): boolean
		if matches(line, ignorePatterns) then
			return true
		end
		return ignore ~= nil and ignore(line)
	end

	local function isError(line: string): boolean
		return matches(line, errorPatterns) and not ignored(line)
	end

	local errorLines: { string } = {}
	local index = 1
	while index <= #source do
		local line = source[index]
		local opensBlock = blockBeginPatterns ~= nil
			and matches(line, blockBeginPatterns)
			and index > 1
			and ignored(source[index - 1])
		if opensBlock then
			local blockEnd = index + 1
			while blockEnd <= #source and not matches(source[blockEnd], blockEndPatterns :: { string }) do
				blockEnd += 1
			end
			if blockEnd <= #source then
				index = blockEnd + 1
				continue
			end
		end
		if isError(line) then
			table.insert(errorLines, line)
		end
		index += 1
	end
	return errorLines
end

local function splitLines(text: unknown): { string }
	if type(text) ~= "string" then
		error("console text must be a string", 3)
	end
	local normalized = string.gsub(text, "\r\n", "\n")
	normalized = string.gsub(normalized, "\r", "\n")
	local lines: { string } = {}
	local from = 1
	while true do
		local at = string.find(normalized, "\n", from, true)
		if at == nil then
			if from <= #normalized then
				table.insert(lines, string.sub(normalized, from))
			end
			return lines
		end
		table.insert(lines, string.sub(normalized, from, at - 1))
		from = at + 1
	end
end

local function classifyConsoleText(text: unknown, options: ClassifyOptions?): { string }
	return classifyConsole(splitLines(text), options)
end

return {
	DEFAULT_ERROR_PATTERNS = DEFAULT_ERROR_PATTERNS,
	DEFAULT_BLOCK_BEGIN_PATTERNS = DEFAULT_BLOCK_BEGIN_PATTERNS,
	DEFAULT_BLOCK_END_PATTERNS = DEFAULT_BLOCK_END_PATTERNS,
	classifyConsole = classifyConsole,
	classifyConsoleText = classifyConsoleText,
	splitConsoleLines = splitLines,
}
