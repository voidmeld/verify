--!strict

local path = require "@std/path"
local query = require "@std/syntax/query"
local syntax = require "@std/syntax"
local utils = require "@std/syntax/utils"

type Violation = {
	lintname: string,
	location: syntax.Span,
	message: string,
	severity: "error" | "warning" | "info" | "hint",
	sourcepath: path.Path?,
}

type Token = { text: string, location: syntax.Span }
type ConstantString = { quoteStyle: string, value: Token, location: syntax.Span }
type InterpString = { strings: { Token } }

local function asConstantString(node: syntax.CstNode): ConstantString?
	return (utils.isExprConstantString(node) :: unknown) :: ConstantString?
end

local function asInterpString(node: syntax.CstNode): InterpString?
	return (utils.isExprInterpString(node) :: unknown) :: InterpString?
end

local NAME = "bad_string_escape"

local VALID: { [string]: boolean } = {
	a = true,
	b = true,
	f = true,
	n = true,
	r = true,
	t = true,
	v = true,
	z = true,
	x = true,
	u = true,
	["\\"] = true,
	['"'] = true,
	["'"] = true,
	["`"] = true,
	["\n"] = true,
	["\r"] = true,
	["0"] = true,
	["1"] = true,
	["2"] = true,
	["3"] = true,
	["4"] = true,
	["5"] = true,
	["6"] = true,
	["7"] = true,
	["8"] = true,
	["9"] = true,
}

local function badEscapes(text: string): { string }
	local found: { string } = {}
	local seen: { [string]: boolean } = {}

	local index = 1
	local limit = #text
	while index <= limit do
		if string.sub(text, index, index) == "\\" then
			local escaped = string.sub(text, index + 1, index + 1)
			if escaped ~= "" and not VALID[escaped] and not seen[escaped] then
				seen[escaped] = true
				table.insert(found, escaped)
			end
			index += 2
		else
			index += 1
		end
	end

	return found
end

local function message(escapes: { string }): string
	local quoted: { string } = {}
	for _, escape in escapes do
		table.insert(quoted, ("`\\%s`"):format(escape))
	end
	return ("%s is not a Luau escape sequence; the backslash is dropped and the string is not what it reads as."):format(
		table.concat(quoted, ", ")
	)
end

local function lint(cst: syntax.CstStatBlock, sourcepath: path.Path?, _context: unknown): { Violation }
	local violations: { Violation } = {}

	local function report(location: syntax.Span, text: string)
		local escapes = badEscapes(text)
		if #escapes == 0 then
			return
		end
		table.insert(violations, {
			lintname = NAME,
			location = location,
			message = message(escapes),
			severity = "warning" :: "warning",
			sourcepath = sourcepath,
		})
	end

	query.findAllFromRoot(cst, asConstantString):forEach(function(node: ConstantString)
		if node.quoteStyle ~= "block" then
			report(node.location, node.value.text)
		end
	end)

	query.findAllFromRoot(cst, asInterpString):forEach(function(node: InterpString)
		for _, segment in node.strings do
			report(segment.location, segment.text)
		end
	end)

	return violations
end

return table.freeze { name = NAME, lint = lint }
