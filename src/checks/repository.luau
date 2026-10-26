--!strict

local fs = require "@std/fs"
local process = require "@std/process"
local Walk = require "./walk"
local Denylist = require "./denylist"
local Policy = require "../lute/type-policy"

export type Selection = { root: string?, untracked: boolean?, suffixes: { string }?, exclude: { [string]: boolean }? }
export type Scan = Selection & { rules: { Denylist.Rule }, allowedLiterals: Denylist.Allowances? }
export type Boundary = {
	root: string,
	rules: { Denylist.Rule },
	exclude: string?,
	allowMissing: boolean?,
	allowEmpty: boolean?,
}

local function selected(config: Selection): { string }
	local suffixes: { string } = config.suffixes or { "" }
	local argv = { "git", "ls-files", "--cached", "-z" }
	if config.untracked then
		table.insert(argv, "--others")
		table.insert(argv, "--exclude-standard")
	end
	local listed = process.run(argv, { cwd = config.root or "." })
	assert(listed.ok, "could not enumerate repository files: " .. listed.stderr)
	local found: { string } = {}
	local seen: { [string]: boolean } = {}
	for path in string.gmatch(listed.stdout, "[^%z]+") do
		if seen[path] or (config.exclude ~= nil and config.exclude[path]) then
			continue
		end
		seen[path] = true
		for _, suffix in suffixes do
			if suffix == "" or string.sub(path, -#suffix) == suffix then
				if fs.exists((config.root or ".") .. "/" .. path) then
					table.insert(found, path)
				end
				break
			end
		end
	end
	table.sort(found)
	return found
end

local function leakage(config: Scan): { string }
	local findings: { string } = {}
	for _, path in selected(config) do
		local source = fs.readFileToString((config.root or ".") .. "/" .. path)
		for _, finding in Denylist.scan(path, source, config.rules, config.allowedLiterals) do
			table.insert(findings, finding)
		end
	end
	return findings
end

local function boundary(config: Boundary): { string }
	if not fs.exists(config.root) and config.allowMissing then
		return {}
	end
	local findings: { string } = {}
	local count = 0
	for _, file in Walk.files(config.root, { ".luau" }) do
		if config.exclude ~= nil and string.match(file.path, config.exclude) ~= nil then
			continue
		end
		count += 1
		for _, finding in Denylist.scan(file.path, file.contents, config.rules) do
			table.insert(findings, finding)
		end
	end
	if count == 0 and not config.allowEmpty then
		table.insert(findings, config.root .. ": no source files")
	end
	return findings
end

local function noAny(config: Selection): { string }
	local selection = table.clone(config)
	selection.suffixes = { ".luau" }
	local findings: { string } = {}
	for _, path in selected(selection) do
		local source = fs.readFileToString((config.root or ".") .. "/" .. path)
		if string.match(source, "^%-%-!strict%s") == nil then
			table.insert(findings, path .. ":1: maintained Luau requires --!strict")
		end
		for _, line in Policy.nonStrict(source) do
			table.insert(findings, ("%s:%d: weakening strict checking is forbidden"):format(path, line))
		end
		for _, line in Policy.explicitAny(source) do
			table.insert(findings, ("%s:%d: explicit any is forbidden"):format(path, line))
		end
	end
	return findings
end

local SPEC_STYLE: { { pattern: string, why: string } } = {
	{ pattern = "%f[%w_][%w_]+%s*:case%(", why = "registers a case with colon syntax; use it(...)" },
	{ pattern = "%f[%w_][%w_]+%s*:expect%(", why = "expects through a context; use expect(...)" },
	{ pattern = "%f[%w_]Test%.it%(", why = "calls Test.it in a body; declare local it once" },
	{ pattern = "%f[%w_]Test%.expect%(", why = "calls Test.expect in a body; declare local expect once" },
	{ pattern = "%f[%w_]Test%.describe%(", why = "calls Test.describe in a body; declare local describe once" },
}

local function specStyle(config: Selection): { string }
	local selection = table.clone(config)
	selection.suffixes = { ".verify.luau" }
	local findings: { string } = {}
	for _, path in selected(selection) do
		local source = fs.readFileToString((config.root or ".") .. "/" .. path)
		for _, rule in SPEC_STYLE do
			local at = string.find(source, rule.pattern)
			if at ~= nil then
				local _, breaks = string.gsub(string.sub(source, 1, at), "\n", "")
				table.insert(findings, ("%s:%d: %s"):format(path, breaks + 1, rule.why))
			end
		end
	end
	return findings
end

return { selected = selected, leakage = leakage, boundary = boundary, noAny = noAny, specStyle = specStyle }
