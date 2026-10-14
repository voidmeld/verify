--!strict

local fs = require "@std/fs"

local Chunk = require "./chunk"
local Datatypes = require "../roblox/datatypes"

export type Environment = { [string]: unknown }

export type Options = {
	aliases: { [string]: string }?,
	hostPaths: { string }?,
	requireHost: ((module: string) -> unknown)?,
}

export type Loader = {
	require: (path: string) -> unknown,
}

local requireRuntime = (require :: unknown) :: (string) -> unknown

local function parent(path: string): string
	return string.match(path, "^(.*)/[^/]*$") or ""
end

local function join(directory: string, tail: string): string
	return if directory == "" then tail else directory .. "/" .. tail
end

local function normalize(path: string): string
	local parts: { string } = {}
	for part in string.gmatch(path, "[^/]+") do
		if part == ".." then
			assert(#parts > 0, "a module path leaves the working directory: " .. path)
			table.remove(parts)
		elseif part ~= "." then
			table.insert(parts, part)
		end
	end
	return table.concat(parts, "/")
end

local function locate(module: string): string
	if string.sub(module, -5) == ".luau" then
		if fs.exists(module) then
			return module
		end
	elseif fs.exists(module .. ".luau") then
		return module .. ".luau"
	elseif fs.exists(module .. "/init.luau") then
		return module .. "/init.luau"
	end
	error("no module at " .. module, 0)
end

local function moduleOf(file: string): string
	return if string.sub(file, -10) == "/init.luau" or file == "init.luau"
		then parent(file)
		else string.sub(file, 1, -6)
end

local function warn(...: unknown)
	local parts: { string } = {}
	for index = 1, select("#", ...) do
		table.insert(parts, tostring((select(index, ...))))
	end
	print("[warn] " .. table.concat(parts, " "))
end

local function new(options: Options?): Loader
	local settings: Options = options or {}
	local aliases: { [string]: string } = settings.aliases or {}
	local hostPaths: { string } = settings.hostPaths or {}
	local resolved: { [string]: string } = {}
	local loaded: { [string]: unknown } = {}
	local loading: { [string]: boolean } = {}
	local environments = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [unknown]: Environment }
	local globals = (
		setmetatable({ warn = warn, typeof = Datatypes.typeof }, { __index = _G }) :: unknown
	) :: Environment

	local function file(module: string): string
		local known = resolved[module]
		if known == nil then
			known = locate(module)
			resolved[module] = known
		end
		return known
	end

	local function hosted(path: string): boolean
		for _, prefix in hostPaths do
			if string.sub(path, 1, #prefix) == prefix then
				return true
			end
		end
		return false
	end

	local function import(path: string): unknown
		if loading[path] then
			error("a module requires itself through a cycle: " .. path, 0)
		end
		local cached = loaded[path]
		if cached ~= nil then
			return cached
		end
		local module = moduleOf(path)
		if hosted(path) then
			local requireHost = settings.requireHost
			assert(requireHost ~= nil, "a loader with hostPaths needs requireHost")
			local value = requireHost(module)
			loaded[path] = value
			return value
		end
		local directory = if string.sub(path, -10) == "/init.luau" then parent(module) else parent(path)
		local environment = (setmetatable({}, { __index = globals }) :: unknown) :: Environment
		environment.require = function(request: string): unknown
			if string.sub(request, 1, 5) == "@std/" or string.sub(request, 1, 6) == "@lute/" then
				return requireRuntime(request)
			end
			local alias, tail = string.match(request, "^@([^/]+)/(.+)$")
			if alias == "self" then
				return import(file(normalize(join(module, tail :: string))))
			elseif alias ~= nil then
				local root = aliases[alias]
				assert(root ~= nil, `{path} requires an unknown alias: {request}`)
				return import(file(normalize(join(root, tail :: string))))
			end
			assert(
				string.sub(request, 1, 2) == "./" or string.sub(request, 1, 3) == "../",
				`{path} requires an unsupported path: {request}`
			)
			return import(file(normalize(join(directory, request))))
		end
		environment.getfenv = function(target: unknown): Environment
			if type(target) == "function" then
				return environments[target] or environment
			end
			return environment
		end
		loading[path] = true
		local ok, value = pcall(function(): unknown
			return Chunk.load(
				fs.readFileToString(path),
				{ name = "./" .. path, environment = environment, injectGlobals = false }
			)()
		end)
		loading[path] = nil
		if not ok then
			error(value, 0)
		end
		if type(value) == "function" then
			environments[value] = environment
		end
		loaded[path] = value
		return value
	end

	return {
		require = function(path: string): unknown
			return import(file(normalize(path)))
		end,
	}
end

return { new = new }
