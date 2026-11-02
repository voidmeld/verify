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

type Call = syntax.CstExprCall

local WARNING: "warning" = "warning"

local NAME = "type_check_inside_call"

local CHECKERS: { [string]: boolean } = { type = true, typeof = true }

local COMPARISONS: { [string]: boolean } = {
	["=="] = true,
	["~="] = true,
	["<"] = true,
	["<="] = true,
	[">"] = true,
	[">="] = true,
}

local function unwrapGroups(expr: syntax.CstExpr): syntax.CstExpr
	local current = expr
	while true do
		local group = utils.isExprGroup(current)
		if group == nil then
			return current
		end
		current = group.expression
	end
end

local function soleArgument(call: Call): syntax.CstExpr?
	local only: syntax.CstExpr? = nil
	local seen = 0
	for _, argument in call.arguments do
		seen += 1
		if seen > 1 then
			return nil
		end
		only = argument
	end
	return only
end

local function checkerName(call: Call): string?
	local func = utils.isExprGlobal(call.func)
	if func == nil or not CHECKERS[func.name.text] then
		return nil
	end
	return func.name.text
end

local function lint(cst: syntax.CstStatBlock, sourcepath: path.Path?, _context: unknown): { Violation }
	return query.findAllFromRoot(cst, utils.isExprCall):mapToArray(function(call: Call): Violation?
		local name = checkerName(call)
		if name == nil then
			return nil
		end

		local argument = soleArgument(call)
		if argument == nil then
			return nil
		end

		local binary = utils.isExprBinary(unwrapGroups(argument))
		if binary == nil or not COMPARISONS[binary.operator.text] then
			return nil
		end

		local operator = binary.operator.text
		return {
			lintname = NAME,
			location = call.location,
			message = ('`%s(a %s b)` always answers "boolean". The comparison belongs outside the call: `%s(a) %s b`.'):format(
				name,
				operator,
				name,
				operator
			),
			severity = WARNING,
			sourcepath = sourcepath,
		}
	end)
end

return table.freeze { name = NAME, lint = lint }
