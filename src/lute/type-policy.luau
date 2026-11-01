--!strict

local parser = require "@std/syntax/parser"
local visitor = require "@std/syntax/visitor"

local function explicitAny(source: string): { number }
	local parsed = parser.parse(source)
	local lines: { number } = {}
	local walk = visitor.create()
	walk.visitTypeReference = function(node)
		if node.prefix == nil and node.name.text == "any" then
			table.insert(lines, node.location.beginLine)
		end
		return true
	end
	visitor.visit(parsed.root, walk)
	return lines
end

local function casts(source: string): { number }
	local parsed = parser.parse(source)
	local lines: { number } = {}
	local walk = visitor.create()
	walk.visitExprTypeAssertion = function(node)
		table.insert(lines, node.operator.location.beginLine)
		return true
	end
	visitor.visit(parsed.root, walk)
	return lines
end

local function nonStrict(source: string): { number }
	local parsed = parser.parse(source)
	local lines: { number } = {}
	local walk = visitor.create()
	walk.visitToken = function(token)
		for _, trivia in { token.leadingTrivia, token.trailingTrivia } do
			for _, item in trivia do
				if string.match(item.text, "^%-%-!nonstrict%s*$") or string.match(item.text, "^%-%-!nocheck%s*$") then
					table.insert(lines, item.location.beginLine)
				end
			end
		end
		return true
	end
	visitor.visit(parsed.root, walk)
	walk.visitToken(parsed.eof)
	return lines
end

return { explicitAny = explicitAny, casts = casts, nonStrict = nonStrict }
