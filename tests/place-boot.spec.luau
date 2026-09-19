--!strict

local test = require "@std/test"

local Roblox = require "../src/roblox"

local PlaceBoot = Roblox.placeBoot

type Node = {
	className: string,
	name: string,
	parent: Node?,
	children: { Node },
	values: { [string]: any },
	signals: { [string]: any },
	propertySignals: { [string]: any },
	attributes: { [string]: any },
}

local function fakeEngine(members: { [string]: { [string]: string } }?): any
	local memberTypes = members or {}
	local engine: any = {}
	local nodes: { [any]: Node } = {}
	local services: { [string]: any } = {}

	local function make(className: string): any
		local object: any = {}
		local state: Node = {
			className = className,
			name = className,
			parent = nil,
			children = {},
			values = {},
			signals = {},
			propertySignals = {},
			attributes = {},
		}
		nodes[object] = state
		setmetatable(object, {
			__index = function(_self: any, key: string): any
				if key == "ClassName" then
					return state.className
				end
				if key == "Name" then
					return state.values.Name or state.name
				end
				if key == "Parent" then
					return state.parent
				end
				if key == "GetChildren" then
					return function(): { any }
						local out: { any } = {}
						for _, child in state.children do
							out[#out + 1] = child
						end
						return out
					end
				end
				if key == "FindFirstChild" then
					return function(_self2: any, wanted: string): any
						for _, child in state.children do
							if nodes[child].values.Name == wanted or nodes[child].name == wanted then
								return child
							end
						end
						return nil
					end
				end
				if key == "SetAttribute" then
					return function(_self2: any, name: string, value: any)
						state.attributes[name] = value
					end
				end
				if key == "GetAttributes" then
					return function(): { [string]: any }
						return state.attributes
					end
				end
				if key == "GetFullName" then
					return function(): string
						return state.name
					end
				end
				return state.values[key]
			end,
			__newindex = function(_self: any, key: string, value: any)
				if key == "Parent" then
					local previous = state.parent
					if previous ~= nil then
						local siblings = nodes[previous :: any].children
						for index, child in siblings do
							if child == _self then
								table.remove(siblings, index)
								break
							end
						end
					end
					state.parent = value
					if value ~= nil then
						table.insert(nodes[value].children, _self)
					end
					return
				end
				state.values[key] = value
			end,
		})
		return object
	end

	engine.game = make "DataModel"
	nodes[engine.game].name = "game"

	engine.newInstance = function(className: string, _raw: boolean?): any
		return make(className)
	end
	engine.stateOf = function(object: any): Node
		return nodes[object]
	end
	engine.service = function(name: string): any
		local existing = services[name]
		if existing == nil then
			existing = make(name)
			nodes[existing].name = name
			nodes[existing].values.Name = name
			existing.Parent = engine.game
			services[name] = existing
		end
		return existing
	end
	engine.surface = {
		services = { Workspace = true, ReplicatedStorage = true, ServerScriptService = true, StarterGui = true },
		memberKind = function(className: string, key: string): string?
			local declared = memberTypes[className]
			if declared ~= nil and declared[key] ~= nil then
				return "property"
			end
			return nil
		end,
		memberType = function(className: string, key: string): string?
			local declared = memberTypes[className]
			return if declared ~= nil then declared[key] else nil
		end,
	}
	engine.datatypes = {
		Enum = { ProximityPromptStyle = { Custom = "Enum.ProximityPromptStyle.Custom" } },
	}
	engine.attributesOf = function(object: any): { [string]: any }
		return nodes[object].attributes
	end
	return engine
end

local function host(files: { [string]: string }): Roblox.PlaceBootHost
	return {
		readFile = function(path: string): string
			local text = files[path]
			if text == nil then
				error("no such file: " .. path, 0)
			end
			return text
		end,
		compile = function(source: string): any
			return source
		end,
		load = function(bytecode: any, _chunkName: string, _environment: { [string]: any }): any
			return function(): any
				return bytecode
			end
		end,
		encodeJson = function(_value: any): string
			return "{}"
		end,
		decodeJson = function(text: string): any
			return (require "@std/json").deserialize(text)
		end,
	}
end

local function fileSystem(
	files: { [string]: string },
	dirs: { [string]: { { name: string, type: string } } }
): Roblox.PlaceBootFiles
	return {
		exists = function(path: string): boolean
			return files[path] ~= nil or dirs[path] ~= nil
		end,
		fileType = function(path: string): string
			return if dirs[path] ~= nil then "dir" else "file"
		end,
		listDirectory = function(path: string): { { name: string, type: string } }
			return dirs[path] or {}
		end,
	}
end

test.suite("place boot glob patterns", function(suite)
	suite:case("turns a single star into a segment-local wildcard that does not cross a slash", function(assert)
		local pattern = PlaceBoot.globToPattern "src/*.luau"
		assert.that(string.match("src/main.luau", pattern) ~= nil, "expected a value")
		assert.that(string.match("src/deep/main.luau", pattern) == nil, "expected no value")
	end)

	suite:case(
		"turns a double star into a wildcard that crosses slashes and absorbs the following slash",
		function(assert)
			local pattern = PlaceBoot.globToPattern "src/**/main.luau"
			assert.that(string.match("src/main.luau", pattern) ~= nil, "expected a value")
			assert.that(string.match("src/a/b/main.luau", pattern) ~= nil, "expected a value")
		end
	)

	suite:case("treats a question mark as exactly one non-slash character", function(assert)
		local pattern = PlaceBoot.globToPattern "a?.luau"
		assert.that(string.match("ab.luau", pattern) ~= nil, "expected a value")
		assert.that(string.match("a.luau", pattern) == nil, "expected no value")
		assert.that(string.match("a/b.luau", pattern) == nil, "expected no value")
	end)

	suite:case("escapes the Lua pattern metacharacters so a literal dot matches only a dot", function(assert)
		local pattern = PlaceBoot.globToPattern "a.luau"
		assert.that(string.match("a.luau", pattern) ~= nil, "expected a value")
		assert.that(string.match("axluau", pattern) == nil, "expected no value")
	end)

	suite:case("anchors both ends so a prefix or suffix alone does not match", function(assert)
		local pattern = PlaceBoot.globToPattern "main.luau"
		assert.that(string.match("main.luau", pattern) ~= nil, "expected a value")
		assert.that(string.match("src/main.luau", pattern) == nil, "expected no value")
		assert.that(string.match("main.luau.bak", pattern) == nil, "expected no value")
	end)
end)

test.suite("place boot script classes", function(suite)
	suite:case("reads a client suffix as a local script and strips the suffix from the name", function(assert)
		local className, base = PlaceBoot.scriptClass "Widget.client.luau"
		assert.eq(className, "LocalScript")
		assert.eq(base, "Widget")
	end)

	suite:case("reads a server suffix as a script and strips the suffix from the name", function(assert)
		local className, base = PlaceBoot.scriptClass "Widget.server.luau"
		assert.eq(className, "Script")
		assert.eq(base, "Widget")
	end)

	suite:case("reads a bare luau file as a module script", function(assert)
		local className, base = PlaceBoot.scriptClass "Widget.luau"
		assert.eq(className, "ModuleScript")
		assert.eq(base, "Widget")
	end)

	suite:case("refuses a file that is not luau at all", function(assert)
		assert.that(PlaceBoot.scriptClass "Widget.json" == nil, "expected nil")
		assert.that(PlaceBoot.scriptClass "Widget" == nil, "expected nil")
	end)
end)

test.suite("place boot commit stabilizing", function(suite)
	suite:case("replaces a forty-hex run with the neutral token so a line compares across builds", function(assert)
		local sha = string.rep("a", 40)
		assert.eq(PlaceBoot.stabilizeCommit("built " .. sha .. " ok"), "built " .. PlaceBoot.COMMIT_TOKEN .. " ok")
	end)

	suite:case("leaves a shorter or longer hex run alone", function(assert)
		local short = string.rep("a", 39)
		assert.eq(PlaceBoot.stabilizeCommit(short), short)
	end)

	suite:case("replaces every commit on one line, not only the first", function(assert)
		local sha = string.rep("b", 40)
		local line = sha .. " and " .. sha
		assert.eq(PlaceBoot.stabilizeCommit(line), PlaceBoot.COMMIT_TOKEN .. " and " .. PlaceBoot.COMMIT_TOKEN)
	end)
end)

test.suite("place boot alias resolution", function(suite)
	local aliases = { Shared = "shared", Root = "." }

	suite:case("joins a known alias root to the rest of the target", function(assert)
		assert.eq(PlaceBoot.resolveAlias(aliases, "@Shared/thing/here"), "shared/thing/here")
	end)

	suite:case("returns nothing for an alias the consumer never declared", function(assert)
		assert.that(PlaceBoot.resolveAlias(aliases, "@Unknown/thing") == nil, "expected nil")
	end)

	suite:case("returns nothing for a target that is not an alias at all", function(assert)
		assert.that(PlaceBoot.resolveAlias(aliases, "./sibling") == nil, "expected nil")
		assert.that(PlaceBoot.resolveAlias(aliases, "plain") == nil, "expected nil")
	end)
end)

test.suite("place boot source cache", function(suite)
	suite:case("reads a path once and serves the same text afterwards", function(assert)
		local reads = 0
		local cache = PlaceBoot.createCache {
			readFile = function(_path: string): string
				reads += 1
				return "body"
			end,
			compile = function(source: string): any
				return source
			end,
			load = function(bytecode: any, _chunk: string, _environment: { [string]: any }): any
				return bytecode
			end,
			encodeJson = function(): string
				return ""
			end,
			decodeJson = function(): any
				return nil
			end,
		}
		assert.eq(cache.read "a.luau", "body")
		assert.eq(cache.read "a.luau", "body")
		assert.eq(reads, 1)
	end)

	suite:case("compiles a path once and serves the same bytecode afterwards", function(assert)
		local compiles = 0
		local cache = PlaceBoot.createCache {
			readFile = function(_path: string): string
				return "body"
			end,
			compile = function(source: string): any
				compiles += 1
				return source .. "!"
			end,
			load = function(bytecode: any, _chunk: string, _environment: { [string]: any }): any
				return bytecode
			end,
			encodeJson = function(): string
				return ""
			end,
			decodeJson = function(): any
				return nil
			end,
		}
		assert.eq(cache.bytecode "a.luau", "body!")
		assert.eq(cache.bytecode "a.luau", "body!")
		assert.eq(compiles, 1)
	end)

	suite:case("names the chunk after the path so a failure points at the file", function(assert)
		local seen = ""
		local cache = PlaceBoot.createCache {
			readFile = function(): string
				return "body"
			end,
			compile = function(source: string): any
				return source
			end,
			load = function(_bytecode: any, chunkName: string, _environment: { [string]: any }): any
				seen = chunkName
				return nil
			end,
			encodeJson = function(): string
				return ""
			end,
			decodeJson = function(): any
				return nil
			end,
		}
		cache.load("dir/a.luau", {})
		assert.eq(seen, "@dir/a.luau")
	end)
end)

test.suite("place boot project tree", function(suite)
	local function build(
		project: string,
		files: { [string]: string },
		dirs: any,
		opaque: Roblox.PlaceBootOpaque?,
		members: any?
	): (any, any)
		local all = table.clone(files)
		all["p.project.json"] = project
		local engine = fakeEngine(members)
		local deps: Roblox.PlaceBootTreeDeps = {
			cache = PlaceBoot.createCache(host(all)),
			host = host(all),
			files = fileSystem(all, dirs),
			opaque = opaque,
		}
		return engine, PlaceBoot.buildTree(engine, "p.project.json", deps)
	end

	suite:case("mounts a directory of scripts and records a source for each one", function(assert)
		local project = [[{"tree":{"ServerScriptService":{"Mod":{"$path":"src"}}}}]]
		local engine, mounted = build(project, {
			["src/Alpha.server.luau"] = "a",
			["src/Beta.luau"] = "b",
		}, {
			src = { { name = "Alpha.server.luau", type = "file" }, { name = "Beta.luau", type = "file" } },
		})
		local names: { string } = {}
		for object, path in mounted.sources do
			names[#names + 1] = engine.stateOf(object).name .. "=" .. path
		end
		table.sort(names)
		assert.eq(#names, 2)
		assert.eq(names[1], "Alpha=src/Alpha.server.luau")
		assert.eq(names[2], "Beta=src/Beta.luau")
	end)

	suite:case("counts only the running scripts, never the module scripts, as scripts to run", function(assert)
		local project = [[{"tree":{"ServerScriptService":{"Mod":{"$path":"src"}}}}]]
		local _engine, mounted = build(project, {
			["src/Alpha.server.luau"] = "a",
			["src/Beta.luau"] = "b",
			["src/Gamma.client.luau"] = "c",
		}, {
			src = {
				{ name = "Alpha.server.luau", type = "file" },
				{ name = "Beta.luau", type = "file" },
				{ name = "Gamma.client.luau", type = "file" },
			},
		})
		assert.eq(#mounted.scripts, 2)
	end)

	suite:case("promotes an init file to the folder itself rather than mounting a child", function(assert)
		local project = [[{"tree":{"ServerScriptService":{"Mod":{"$path":"src"}}}}]]
		local engine, mounted = build(project, {
			["src/init.luau"] = "i",
			["src/Leaf.luau"] = "l",
		}, {
			src = { { name = "init.luau", type = "file" }, { name = "Leaf.luau", type = "file" } },
		})
		local container: any = nil
		for object, path in mounted.sources do
			if path == "src/init.luau" then
				container = object
			end
		end
		assert.that(container ~= nil, "expected a value")
		assert.eq(engine.stateOf(container).className, "ModuleScript")
		assert.eq(engine.stateOf(container).name, "Mod")
	end)

	suite:case("skips a path the project's ignore globs name", function(assert)
		local project = [[{"globIgnorePaths":["src/Skip.luau"],"tree":{"ServerScriptService":{"Mod":{"$path":"src"}}}}]]
		local _engine, mounted = build(project, {
			["src/Keep.luau"] = "k",
			["src/Skip.luau"] = "s",
		}, {
			src = { { name = "Keep.luau", type = "file" }, { name = "Skip.luau", type = "file" } },
		})
		local paths: { string } = {}
		for _object, path in mounted.sources do
			paths[#paths + 1] = path
		end
		assert.eq(#paths, 1)
		assert.eq(paths[1], "src/Keep.luau")
	end)

	suite:case("hands an opaque model path to the consumer's hook and stamps the consumer's attribute", function(assert)
		local project = [[{"tree":{"ServerScriptService":{"Art":{"$path":"art/thing.rbxm"}}}}]]
		local filled: { string } = {}
		local engine, _mounted = build(project, {}, {}, {
			attribute = "ConsumerUnmounted",
			fill = function(_engine: any, _object: any, path: string)
				filled[#filled + 1] = path
			end,
		})
		assert.eq(#filled, 1)
		assert.eq(filled[1], "art/thing.rbxm")
		local service = engine.service "ServerScriptService"
		local model = service:FindFirstChild "Art"
		assert.that(model ~= nil, "expected a value")
		assert.eq(engine.attributesOf(model).ConsumerUnmounted, "art/thing.rbxm")
	end)

	suite:case(
		"mounts an opaque model with no attribute and no hook when the consumer declares neither",
		function(assert)
			local project = [[{"tree":{"ServerScriptService":{"Art":{"$path":"art/thing.rbxmx"}}}}]]
			local engine, _mounted = build(project, {}, {}, nil)
			local model = engine.service("ServerScriptService"):FindFirstChild "Art"
			assert.that(model ~= nil, "expected a value")
			assert.eq(engine.stateOf(model).className, "Model")
			assert.that(next(engine.attributesOf(model)) == nil, "expected nil")
		end
	)

	suite:case("applies a declared property to a mounted node", function(assert)
		local project = [[{"tree":{"Workspace":{"Thing":{"$className":"Part","$properties":{"Anchored":true}}}}}]]
		local engine, _mounted = build(project, {}, {}, nil, { Part = { Anchored = "boolean" } })
		local thing = engine.service("Workspace"):FindFirstChild "Thing"
		assert.eq(engine.stateOf(thing).values.Anchored, true)
	end)

	suite:case("coerces a declared enum property from its string name to the enum item", function(assert)
		local project =
			[[{"tree":{"Workspace":{"Prompt":{"$className":"ProximityPrompt","$properties":{"Style":"Custom"}}}}}]]
		local engine, _mounted = build(
			project,
			{},
			{},
			nil,
			{ ProximityPrompt = { Style = "EnumProximityPromptStyle" } }
		)
		local prompt = engine.service("Workspace"):FindFirstChild "Prompt"
		assert.eq(engine.stateOf(prompt).values.Style, "Enum.ProximityPromptStyle.Custom")
	end)

	suite:case("ignores a property the class does not declare", function(assert)
		local project = [[{"tree":{"Workspace":{"Thing":{"$className":"Part","$properties":{"Nonsense":1}}}}}]]
		local engine, _mounted = build(project, {}, {}, nil, { Part = { Anchored = "boolean" } })
		local thing = engine.service("Workspace"):FindFirstChild "Thing"
		assert.that(engine.stateOf(thing).values.Nonsense == nil, "expected nil")
	end)

	suite:case("falls back to a folder when the named path does not exist", function(assert)
		local project = [[{"tree":{"ServerScriptService":{"Gone":{"$path":"nowhere"}}}}]]
		local engine, _mounted = build(project, {}, {}, nil)
		local gone = engine.service("ServerScriptService"):FindFirstChild "Gone"
		assert.that(gone ~= nil, "expected a value")
		assert.eq(engine.stateOf(gone).className, "Folder")
	end)

	suite:case("returns the engine's own root as the mounted root", function(assert)
		local project = [[{"tree":{"Workspace":{}}}]]
		local engine, mounted = build(project, {}, {}, nil)
		assert.eq(mounted.root, engine.game)
	end)
end)

local function bootEngine(members: any?): any
	local engine = fakeEngine(members)
	local diagnostics: { any } = {}
	local clock = 0
	local sourceResolver: any = nil
	engine.diagnostics = diagnostics
	engine.serviceMethods = {}
	engine.methods = {
		Destroy = function() end,
	}
	engine.scheduler = {
		advance = function(delta: number)
			clock += delta
		end,
		drain = function() end,
		clock = function(): number
			return clock
		end,
		spawn = function(callback: any, ...: any): any
			if type(callback) == "function" then
				callback(...)
			end
			return callback
		end,
		defer = function() end,
		delay = function() end,
		wait = function(): number
			return 0
		end,
		block = function() end,
		resume = function() end,
		tag = function() end,
		context = function(): any
			return nil
		end,
		onFailure = function() end,
	}
	engine.signal = function(): any
		local handlers: { any } = {}
		return {
			handlers = handlers,
			Connect = function(_self: any, handler: any): any
				handlers[#handlers + 1] = handler
				return { Disconnect = function() end }
			end,
		}
	end
	engine.fire = function(signal: any, ...: any)
		if signal == nil then
			return
		end
		for _, handler in signal.handlers or {} do
			handler(...)
		end
	end
	engine.record = function(kind: string, text: string, source: string?)
		diagnostics[#diagnostics + 1] = { kind = kind, text = text, source = source or "engine" }
	end
	engine.currentSource = function(): string
		return if sourceResolver ~= nil then sourceResolver() else "engine"
	end
	engine.setSourceResolver = function(resolver: any)
		sourceResolver = resolver
	end
	engine.isInstance = function(value: any): boolean
		return type(value) == "table"
	end
	engine.typeName = function(value: any): string
		return type(value)
	end
	engine.outstandingWaits = function(): { any }
		return {}
	end
	engine.frames = function(): number
		return 0
	end
	engine.blocked = function(): number
		return 0
	end
	engine.datatypes.Vector2 = {
		new = function(x: number, y: number): any
			return { X = x, Y = y }
		end,
	}
	engine.datatypes.Enum.AssetFetchStatus = { Success = "Success" }
	engine.datatypes.Enum.PlaybackState = { Completed = "Completed" }
	return engine
end

local function bootOnce(project: string, config: any): (any, any)
	local files = { ["p.project.json"] = project }
	local engine = bootEngine()
	local deps: Roblox.PlaceBootDeps = {
		newEngine = function(): any
			return engine
		end,
		cache = PlaceBoot.createCache(host(files)),
		host = host(files),
		files = fileSystem(files, {}),
	}
	local settings: any = {
		projectPath = "p.project.json",
		identity = { universeId = 7, placeId = 9, placeVersion = 3 },
		witness = { name = "Witness", userId = 11, jobId = "job" },
		aliases = {},
		firstViewport = { x = 1, y = 1 },
		finalViewport = { x = 390, y = 844 },
		frames = 1,
		engineProvidedInput = false,
	}
	for key, value in config do
		settings[key] = value
	end
	return engine, PlaceBoot.run(settings, deps)
end

test.suite("place boot sequence", function(suite)
	suite:case("reaches every stage once, in the order the sequence declares", function(assert)
		local seen: { string } = {}
		local _engine, _report = bootOnce([[{"tree":{"Workspace":{}}}]], {
			observe = function(stage: string)
				seen[#seen + 1] = stage
			end,
		})
		assert.eq(#seen, 6)
		assert.eq(table.concat(seen, ","), "server,player,client,viewport,character,settled")
	end)

	suite:case("offers no player before one joins and the joined player at every later stage", function(assert)
		local withPlayer: { string } = {}
		local _engine, _report = bootOnce([[{"tree":{"Workspace":{}}}]], {
			observe = function(stage: string, view: any)
				if view.player ~= nil and view.playerGui ~= nil then
					withPlayer[#withPlayer + 1] = stage
				end
			end,
		})
		assert.eq(table.concat(withPlayer, ","), "player,client,viewport,character,settled")
	end)

	suite:case("hands the same engine and runtime to the observer that it reports", function(assert)
		local engines: { any } = {}
		local engine, report = bootOnce([[{"tree":{"Workspace":{}}}]], {
			observe = function(_stage: string, view: any)
				engines[#engines + 1] = view.engine
			end,
		})
		assert.eq(engines[1], engine)
		assert.eq(report.engine, engine)
	end)

	suite:case("boots with no observer at all", function(assert)
		local _engine, report = bootOnce([[{"tree":{"Workspace":{}}}]], {})
		assert.that(report.player ~= nil, "expected a player")
		assert.that(report.playerGui ~= nil, "expected a player gui")
	end)

	suite:case("stamps the injected identity onto the data model", function(assert)
		local engine, _report = bootOnce([[{"tree":{"Workspace":{}}}]], {})
		local values = engine.stateOf(engine.game).values
		assert.eq(values.GameId, 7)
		assert.eq(values.PlaceId, 9)
		assert.eq(values.PlaceVersion, 3)
		assert.eq(values.JobId, "job")
	end)

	suite:case("names the witness from the injected name and user id", function(assert)
		local engine, report = bootOnce([[{"tree":{"Workspace":{}}}]], {})
		assert.eq(engine.stateOf(report.player).values.UserId, 11)
		assert.eq(engine.stateOf(report.player).name, "Witness")
	end)

	suite:case("stamps the consumer's ready attributes only when it declares them", function(assert)
		local engine, _report = bootOnce([[{"tree":{"Workspace":{}}}]], {
			attributes = { character = "Ready", workspace = "Composed" },
		})
		assert.eq(engine.attributesOf(engine.service "Workspace").Composed, true)
		local bare = select(1, bootOnce([[{"tree":{"Workspace":{}}}]], {}))
		assert.that(next(bare.attributesOf(bare.service "Workspace")) == nil, "expected no attribute")
	end)

	suite:case("reports the error and warning lines with a commit stabilized, and nothing else", function(assert)
		local sha = string.rep("c", 40)
		local engine, report = bootOnce([[{"tree":{"Workspace":{}}}]], {
			observe = function(stage: string, view: any)
				if stage == "server" then
					view.engine.record("warn", "built " .. sha, "Src")
					view.engine.record("print", "chatter", "Src")
					view.engine.record("error", "broke\nsecond line", "Src")
				end
			end,
		})
		assert.eq(#report.lines, 2)
		assert.eq(report.lines[1], "warn Src: built " .. PlaceBoot.COMMIT_TOKEN)
		assert.eq(report.lines[2], "error Src: broke")
		assert.that(engine ~= nil, "expected an engine")
	end)

	suite:case("lets the consumer replace the line stabilizer entirely", function(assert)
		local _engine, report = bootOnce([[{"tree":{"Workspace":{}}}]], {
			stabilize = function(_line: string): string
				return "redacted"
			end,
			observe = function(stage: string, view: any)
				if stage == "server" then
					view.engine.record("warn", "anything", "Src")
				end
			end,
		})
		assert.eq(report.lines[1], "warn Src: redacted")
	end)
end)
