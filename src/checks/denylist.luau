--!strict

local Walk = require "./walk"

export type Rule =
	{ pattern: string, why: string, plain: boolean?, allMatches: boolean?, exempt: { [string]: string }? }
export type Allowances = { [string]: { string } }

local function scan(path: string, source: string, rules: { Rule }, allowed: Allowances?): { string }
	local literals: { string } = if allowed ~= nil then allowed[path] or {} else {}
	for _, literal in literals do
		assert(#literal > 0, "denylist allowance must not be empty")
		local first = 1
		while true do
			local start, finish = string.find(source, literal, first, true)
			if start == nil or finish == nil then
				break
			end
			source = string.sub(source, 1, start - 1)
				.. string.gsub(literal, "[^\n]", " ")
				.. string.sub(source, finish + 1)
			first = finish + 1
		end
	end
	local findings: { string } = {}
	for _, rule in rules do
		if rule.exempt ~= nil and rule.exempt[path] ~= nil then
			continue
		end
		local cursor = 1
		while cursor <= #source + 1 do
			local offset, finish = string.find(source, rule.pattern, cursor, rule.plain == true)
			if offset == nil or finish == nil then
				break
			end
			cursor = math.max(finish + 1, offset + 1)
			local matched = string.sub(source, offset, finish)
			if rule.exempt ~= nil and rule.exempt[path .. ":" .. matched] ~= nil then
				continue
			end
			table.insert(findings, ("%s:%d: %s"):format(path, Walk.lineOf(source, offset), rule.why))
			if not rule.allMatches then
				break
			end
		end
	end
	return findings
end

return { scan = scan }
