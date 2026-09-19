--!strict

local fs = require "@std/fs"
local test = require "@std/test"

local ENGINE_MOUNTABLE: { [string]: boolean } = {
	["src/bdd.luau"] = true,
	["src/consumer"] = true,
	["src/core"] = true,
	["src/host"] = true,
	["src/roblox"] = true,
}

local LUTE_ONLY = "src/lute"

local ENTRY_POINTS = {
	"src/core/init.luau",
	"src/bdd.luau",
	"src/roblox/init.luau",
	"src/consumer/init.luau",
	"src/host/init.luau",
}

local function isInit(path: string): boolean
	return string.match(path, "/init%.luau$") ~= nil
end

local function directoryOf(path: string): string
	return (string.match(path, "^(.*)/[^/]+$")) :: string
end

local function ascend(path: string): string
	local parent = string.match(path, "^(.*)/[^/]+$")
	return if parent ~= nil then parent else ""
end

local function join(base: string, tail: string): string
	return if base == "" then tail else base .. "/" .. tail
end

local function collect(root: string): { { path: string, request: string } }
	local found: { { path: string, request: string } } = {}
	local function walk(directory: string)
		local entries = fs.listDirectory(directory)
		table.sort(entries, function(left, right)
			return left.name < right.name
		end)
		for _, entry in entries do
			local child = directory .. "/" .. entry.name
			if entry.type == "dir" then
				walk(child)
			elseif string.match(entry.name, "%.luau$") ~= nil then
				local source = fs.readFileToString(child)
				for request in string.gmatch(source, 'require%s*"([^"]+)"') do
					table.insert(found, { path = child, request = request })
				end
				for request in string.gmatch(source, 'require%s*%(%s*"([^"]+)"') do
					table.insert(found, { path = child, request = request })
				end
			end
		end
	end
	walk(root)
	return found
end

local function resolve(path: string, request: string): string?
	local base: string
	local tail: string
	local selfTail = string.match(request, "^@self/(.+)$")
	if selfTail ~= nil then
		base = directoryOf(path)
		tail = selfTail
	elseif string.match(request, "^%.%.?/") ~= nil then
		base = if isInit(path) then ascend(directoryOf(path)) else directoryOf(path)
		tail = request
		while true do
			local up = string.match(tail, "^%.%./(.+)$")
			if up == nil then
				break
			end
			base = ascend(base)
			tail = up
		end
		local here = string.match(tail, "^%./(.+)$")
		if here ~= nil then
			tail = here
		end
	else
		return nil
	end
	local candidate = join(base, tail)
	if fs.exists(candidate .. ".luau") then
		return candidate .. ".luau"
	end
	if fs.exists(candidate .. "/init.luau") then
		return candidate
	end
	return nil
end

local function packageOf(path: string): string
	local package = string.match(path, "^(src/[^/]+)")
	return if package ~= nil then package else path
end

test.suite("module graph host neutrality", function(suite)
	suite:case("engine-mountable packages name no alias other than @self", function(assert)
		local offences: { string } = {}
		for _, site in collect "src" do
			if not ENGINE_MOUNTABLE[packageOf(site.path)] then
				continue
			end
			if string.sub(site.request, 1, 1) == "@" and string.match(site.request, "^@self/") == nil then
				table.insert(offences, site.path .. " requires " .. site.request)
			end
		end
		assert.eq(offences, {})
	end)

	suite:case("directory modules reach outward only through @self children", function(assert)
		local offences: { string } = {}
		for _, site in collect "src" do
			if not ENGINE_MOUNTABLE[packageOf(site.path)] or not isInit(site.path) then
				continue
			end
			if string.match(site.request, "^@self/") == nil then
				table.insert(offences, site.path .. " requires " .. site.request)
			end
		end
		assert.eq(offences, {})
	end)

	suite:case("every engine-mountable require resolves to a real module", function(assert)
		local unresolved: { string } = {}
		for _, site in collect "src" do
			if not ENGINE_MOUNTABLE[packageOf(site.path)] then
				continue
			end
			if resolve(site.path, site.request) == nil then
				table.insert(unresolved, site.path .. " requires " .. site.request)
			end
		end
		assert.eq(unresolved, {})
	end)

	suite:case("the engine-mountable closure never escapes into a host-bound package", function(assert)
		local escapes: { string } = {}
		local seen: { [string]: boolean } = {}
		local queue: { string } = {}
		for _, entry in ENTRY_POINTS do
			table.insert(queue, entry)
			seen[entry] = true
		end
		local sites = collect "src"
		while #queue > 0 do
			local path = table.remove(queue) :: string
			for _, site in sites do
				if site.path ~= path then
					continue
				end
				local target = resolve(site.path, site.request)
				if target == nil then
					continue
				end
				local file = if string.match(target, "%.luau$") ~= nil then target else target .. "/init.luau"
				if not ENGINE_MOUNTABLE[packageOf(file)] then
					table.insert(escapes, site.path .. " reaches " .. file)
					continue
				end
				if not seen[file] then
					seen[file] = true
					table.insert(queue, file)
				end
			end
		end
		assert.eq(escapes, {})
	end)

	suite:case("the excluded package is excluded for a stated host reason", function(assert)
		assert.eq(ENGINE_MOUNTABLE[LUTE_ONLY] == true, false)
		local named = false
		for _, site in collect(LUTE_ONLY) do
			if string.match(site.request, "^@std/") ~= nil then
				named = true
			end
		end
		assert.eq(named, true)
	end)
end)
