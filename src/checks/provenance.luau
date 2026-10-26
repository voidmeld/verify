--!strict

local fs = require "@std/fs"
local process = require "@std/process"
local Walk = require "./walk"

export type Config = {
	forbiddenPaths: { string },
	license: string,
	licensePrefix: string?,
	licenseFragments: { string },
	requiredText: { [string]: { string } }?,
	lock: string?,
	dependencyCommand: { string }?,
	root: string?,
	skip: { string }?,
	suffixes: { string }?,
	descriptors: { string }?,
	noticeNames: { string }?,
	expectedNotices: { [string]: string }?,
	scriptExceptions: { [string]: string }?,
	forbiddenSuffixes: { string }?,
	justifiedSuffixes: { string }?,
}

local function check(config: Config): { string }
	local justifiedSuffixes: { string } = config.justifiedSuffixes or {}
	local forbiddenSuffixes: { string } = config.forbiddenSuffixes or {}
	local descriptors: { string } = config.descriptors or {}
	local noticeNames: { string } = config.noticeNames or {}
	local suffixes: { string } = config.suffixes or { "" }
	local skip: { string } = config.skip or {}
	local findings: { string } = {}
	local function fail(message: string)
		table.insert(findings, message)
	end
	for _, path in config.forbiddenPaths do
		if fs.exists(path) then
			fail(path .. ": forbidden path exists")
		end
	end
	local required = table.clone(config.requiredText or {})
	required[config.license] = config.licenseFragments
	for path, fragments in required do
		if not fs.exists(path) then
			fail(path .. ": required file is absent")
			continue
		end
		local text = fs.readFileToString(path)
		for _, fragment in fragments do
			if string.find(text, fragment, 1, true) == nil then
				fail(path .. ": missing required text: " .. fragment)
			end
		end
		if
			path == config.license
			and config.licensePrefix ~= nil
			and string.sub(text, 1, #config.licensePrefix) ~= config.licensePrefix
		then
			fail(path .. ": invalid license prefix")
		end
	end
	if config.lock ~= nil and not fs.exists(config.lock) then
		fail(config.lock .. ": dependency lock is absent")
	elseif config.dependencyCommand ~= nil then
		local result = process.run(config.dependencyCommand)
		if not result.ok then
			fail("dependency check failed: " .. result.stdout .. result.stderr)
		end
	end
	local function skipped(path: string): boolean
		for _, prefix in skip do
			if string.sub(path, 1, #prefix) == prefix then
				return true
			end
		end
		return false
	end
	local paths: { string } = {}
	if config.root ~= nil then
		for _, path in
			Walk.pathsSkipping(config.root, { "" }, function(relative, kind)
				return kind == "dir" and skipped(relative .. "/")
			end)
		do
			local relative = string.sub(path, #config.root + 2)
			if skipped(relative) then
				continue
			end
			local basename = string.match(relative, "([^/]+)$") or relative
			local include = false
			for _, suffix in suffixes do
				if suffix == "" or string.sub(relative, -#suffix) == suffix then
					include = true
				end
			end
			for _, name in noticeNames do
				if basename == name then
					include = true
				end
			end
			if include then
				table.insert(paths, path)
			end
		end
	end
	for _, path in paths do
		local relative = string.sub(path, #(config.root :: string) + 2)
		local basename = string.match(relative, "([^/]+)$") or relative
		for _, name in descriptors do
			if basename == name then
				fail(relative .. ": ungoverned dependency descriptor")
			end
		end
		for _, name in noticeNames do
			if basename == name and (config.expectedNotices == nil or config.expectedNotices[relative] == nil) then
				fail(relative .. ": unaccounted license or notice")
			end
		end
		for _, suffix in forbiddenSuffixes do
			if string.sub(relative, -#suffix) == suffix then
				fail(relative .. ": prohibited source language")
			end
		end
		for _, suffix in justifiedSuffixes do
			if
				string.sub(relative, -#suffix) == suffix
				and (config.scriptExceptions == nil or config.scriptExceptions[relative] == nil)
			then
				fail(relative .. ": script requires justification")
			end
		end
	end
	for path, why in pairs(config.expectedNotices or {}) do
		local full = (config.root or ".") .. "/" .. path
		if not fs.exists(full) then
			fail(path .. ": missing notice: " .. why)
		elseif #fs.readFileToString(full) < 40 then
			fail(path .. ": notice is empty")
		end
	end
	for path, why in pairs(config.scriptExceptions or {}) do
		if not fs.exists((config.root or ".") .. "/" .. path) then
			fail(path .. ": stale script exception")
		end
		if #why < 20 then
			fail(path .. ": script justification is too short")
		end
	end
	table.sort(findings)
	return findings
end

return check
