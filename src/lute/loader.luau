--!strict

local fs = require "@std/fs"

local Paths = require "../core/path"
local Chunk = require "./chunk"
local Datatypes = require "../roblox/datatypes"

export type Environment = { [string]: unknown }

export type Files = {
	exists: (path: string) -> boolean,
	readFile: (path: string) -> string,
}

export type Options = {
	files: Files?,
	aliases: { [string]: string }?,
	hostPaths: { string }?,
	requireHost: ((module: string) -> unknown)?,
	globals: Environment?,
	transform: ((path: string, source: string) -> string)?,
}

export type Reference = { modulePath: string }

export type Loader = {
	require: (path: string) -> unknown,
	reference: (path: string) -> Reference,
}

local requireRuntime: (string) -> unknown = require

local function inherit(environment: Environment, index: Environment | ((Environment, string) -> unknown))
	setmetatable(environment, { __index = index })
end

local function weakKeys<K, V>(registry: { [K]: V })
	setmetatable(registry, { __mode = "k" })
end

local function parent(path: string): string
	return string.match(path, "^(.*)/[^/]*$") or ""
end

local function join(directory: string, tail: string): string
	return if directory == "" then tail else directory .. "/" .. tail
end

local function normalize(path: string): string
	return (string.gsub(Paths.collapse(path, "a module path leaves the working directory: " .. path), "^/", ""))
end

local function locate(module: string, exists: (string) -> boolean): string
	if string.sub(module, -5) == ".luau" then
		if exists(module) then
			return module
		end
	elseif exists(module .. ".luau") then
		return module .. ".luau"
	elseif exists(module .. "/init.luau") then
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
	local sources: { [string]: string } = {}
	local prefetched: { [string]: boolean } = {}
	local function exists(path: string): boolean
		return sources[path] ~= nil or fs.exists(path)
	end
	local function readFile(path: string): string
		return sources[path] or fs.readFileToString(path)
	end
	local files: Files = settings.files or { exists = exists, readFile = readFile }
	local function prefetch(directory: string)
		if settings.files ~= nil or directory == "" or directory == "." or prefetched[directory] then
			return
		end
		prefetched[directory] = true
		local listed, entries = pcall(fs.listDirectory, directory)
		if not listed then
			return
		end
		for _, entry in entries do
			local child = directory .. "/" .. entry.name
			if entry.type == "dir" and string.sub(entry.name, 1, 1) ~= "." then
				prefetch(child)
			elseif entry.type == "file" and string.sub(entry.name, -5) == ".luau" then
				sources[child] = fs.readFileToString(child)
			end
		end
	end
	local aliases: { [string]: string } = settings.aliases or {}
	local hostPaths: { string } = settings.hostPaths or {}
	local resolved: { [string]: string } = {}
	local loaded: { [string]: unknown } = {}
	local loading: { [string]: boolean } = {}
	local environments: { [unknown]: Environment } = {}
	weakKeys(environments)
	local defaults: Environment = { warn = warn, typeof = Datatypes.typeof }
	local supplied: Environment = settings.globals or {}
	local globals: Environment = {}
	inherit(globals, function(_: Environment, name: string): unknown
		local value = supplied[name]
		if value == nil then
			value = defaults[name]
		end
		if value == nil then
			value = (_G)[name]
		end
		return value
	end)
	for name, value in _G do
		if supplied[name] == nil and defaults[name] == nil then
			rawset(globals, name, value)
		end
	end

	local function file(module: string): string
		local known = resolved[module]
		if known == nil then
			known = locate(module, files.exists)
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
		if not hosted(path) then
			prefetch(parent(path))
		end
		if hosted(path) then
			local requireHost = settings.requireHost
			assert(requireHost ~= nil, "a loader with hostPaths needs requireHost")
			local value = requireHost(module)
			loaded[path] = value
			return value
		end
		local directory = if string.sub(path, -10) == "/init.luau" then parent(module) else parent(path)
		local environment: Environment = {}
		inherit(environment, globals)
		environment.require = function(target: string | Reference): unknown
			if type(target) == "table" then
				return import(file(normalize(target.modulePath)))
			end
			local request = target
			if string.sub(request, 1, 5) == "@std/" or string.sub(request, 1, 6) == "@lute/" then
				return requireRuntime(request)
			end
			local alias, tail = string.match(request, "^@([^/]+)/(.+)$")
			if alias == "self" then
				assert(tail ~= nil)
				return import(file(normalize(join(module, tail))))
			elseif alias ~= nil then
				local root = aliases[alias]
				assert(root ~= nil, `{path} requires an unknown alias: {request}`)
				assert(tail ~= nil)
				return import(file(normalize(join(root, tail))))
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
			local source = files.readFile(path)
			local transform = settings.transform
			if transform ~= nil then
				source = transform(path, source)
			end
			local loaded: unknown =
				Chunk.load(source, { name = "./" .. path, environment = environment, injectGlobals = false })()
			return loaded
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

	local function reference(path: string): Reference
		local made: Reference = { modulePath = path }
		local function attach(value: Reference)
			setmetatable(value, {
				__index = function(_: Reference, child: string): Reference
					return reference(path .. "/" .. child)
				end,
			})
		end
		attach(made)
		return made
	end

	return {
		require = function(path: string): unknown
			return import(file(normalize(path)))
		end,
		reference = reference,
	}
end

return { new = new }
