--!strict

local fs = require "@std/fs"
local parser = require "@std/syntax/parser"
local visitor = require "@std/syntax/visitor"
local syntax = require "@std/syntax"
local Walk = require "./walk"
local Text = require "./comment-text"
local Repository = require "./repository"

export type Config = {
	roots: { string }?,
	files: { string }?,
	configFiles: { string }?,
	selection: Repository.Selection?,
	allowed: { string }?,
	lineDirectives: boolean?,
	licenseFragments: { string }?,
	write: boolean?,
}

local function check(config: Config): { string }
	local configFiles: { string } = config.configFiles or {}
	local files: { string } = config.files or {}
	local roots: { string } = config.roots or {}
	local patterns: { string } = config.allowed or {}
	local findings: { string } = {}
	local seen: { [string]: boolean } = {}
	local function source(path: string)
		if seen[path] or not fs.exists(path) then
			return
		end
		seen[path] = true
		local text = fs.readFileToString(path)
		local parsed = (parser.parse(text) :: unknown) :: { root: syntax.CstStatBlock, eof: syntax.CstToken<string> }
		local walk = visitor.create()
		local removals: { { start: number, finish: number } } = {}
		local offsets: { [number]: boolean } = {}
		walk.visitToken = function(token)
			local view = (token :: unknown) :: {
				leadingTrivia: { { tag: string, text: string, location: { beginLine: number, beginColumn: number } } },
				trailingTrivia: { { tag: string, text: string, location: { beginLine: number, beginColumn: number } } },
			}
			for _, trivia in { view.leadingTrivia, view.trailingTrivia } do
				for _, item in trivia do
					if item.tag == "whitespace" then
						continue
					end
					local lineStart = 1
					for _ = 2, item.location.beginLine do
						lineStart = (string.find(text, "\n", lineStart, true) :: number) + 1
					end
					local start = lineStart + item.location.beginColumn - 1
					local finish = start + #item.text - 1
					assert(string.sub(text, start, finish) == item.text, "could not locate comment trivia")
					local allowed = false
					if
						not config.lineDirectives
						or string.match(string.sub(text, lineStart, start - 1), "^[ \t]*$") ~= nil
					then
						for _, pattern in patterns do
							if string.match(item.text, pattern) ~= nil then
								allowed = true
							end
						end
					end
					if config.licenseFragments ~= nil then
						local license = true
						for _, fragment in config.licenseFragments do
							if string.find(item.text, fragment, 1, true) == nil then
								license = false
							end
						end
						if license then
							allowed = true
						end
					end
					if allowed then
						continue
					end
					if offsets[start] then
						continue
					end
					offsets[start] = true
					table.insert(removals, { start = start, finish = finish })
					table.insert(findings, ("%s:%d: prohibited comment"):format(path, item.location.beginLine))
				end
			end
			return true
		end
		visitor.visit(parsed.root, walk)
		walk.visitToken(parsed.eof)
		if config.write then
			table.sort(removals, function(left, right)
				return left.start > right.start
			end)
			for _, removal in removals do
				text = string.sub(text, 1, removal.start - 1)
					.. string.gsub(string.sub(text, removal.start, removal.finish), "[^\n]", " ")
					.. string.sub(text, removal.finish + 1)
			end
			fs.writeStringToFile(path, text)
		end
	end
	for _, root in roots do
		for _, path in Walk.paths(root, { ".luau" }) do
			source(path)
		end
	end
	for _, path in files do
		source(path)
	end
	if config.selection ~= nil then
		for _, path in Repository.selected(config.selection) do
			source((config.selection.root or ".") .. "/" .. path)
		end
	end
	for _, path in configFiles do
		if not fs.exists(path) then
			continue
		end
		local text = fs.readFileToString(path)
		local starts = Text.hashComments(text)
		for _, start in starts do
			table.insert(findings, ("%s:%d: prohibited config comment"):format(path, Walk.lineOf(text, start)))
		end
		if config.write then
			fs.writeStringToFile(path, Text.withoutHashComments(text, starts))
		end
	end
	if config.write then
		return {}
	end
	table.sort(findings)
	return findings
end

return check
