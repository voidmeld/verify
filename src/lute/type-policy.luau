--!strict

local parser = require "@std/syntax/parser"
local syntax = require "@std/syntax"
local visitor = require "@std/syntax/visitor"

local function explicitAny(source: string): { number }
	local parsed = (parser.parse(source) :: unknown) :: { root: syntax.CstStatBlock }
	local lines: { number } = {}
	local walk = visitor.create()
	walk.visitType = function(node)
		local tag = ((node :: unknown) :: { tag: string }).tag
		if tag == "reference" then
			local reference = (node :: unknown) :: {
				prefix: unknown,
				name: { text: string },
				location: {
					beginLine: number,
				},
			}
			if reference.prefix == nil and reference.name.text == "any" then
				table.insert(lines, reference.location.beginLine)
			end
		end
		return true
	end
	visitor.visit(parsed.root, walk)
	return lines
end

local function nonStrict(source: string): { number }
	local parsed = (parser.parse(source) :: unknown) :: { root: syntax.CstStatBlock, eof: syntax.CstToken<string> }
	local lines: { number } = {}
	local walk = visitor.create()
	walk.visitToken = function(token)
		local view = (token :: unknown) :: {
			leadingTrivia: { { text: string, location: { beginLine: number } } },
			trailingTrivia: { { text: string, location: { beginLine: number } } },
		}
		for _, trivia in { view.leadingTrivia, view.trailingTrivia } do
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

return { explicitAny = explicitAny, nonStrict = nonStrict }
