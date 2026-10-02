--!strict

local Verify = require "../src/core"

local Roblox = require "../src/roblox"
local luau = require "@std/luau"

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

return function(suite: Verify.Harness)
	suite:suite("place boot glob patterns", function()
		suite:case("turns a single star into a segment-local wildcard that does not cross a slash", function(check)
			local pattern = PlaceBoot.globToPattern "src/*.luau"
			assert(string.match("src/main.luau", pattern) ~= nil, "expected a value")
			assert(string.match("src/deep/main.luau", pattern) == nil, "expected no value")
		end)

		suite:case(
			"turns a double star into a wildcard that crosses slashes and absorbs the following slash",
			function(check)
				local pattern = PlaceBoot.globToPattern "src/**/main.luau"
				assert(string.match("src/main.luau", pattern) ~= nil, "expected a value")
				assert(string.match("src/a/b/main.luau", pattern) ~= nil, "expected a value")
			end
		)

		suite:case("treats a question mark as exactly one non-slash character", function(check)
			local pattern = PlaceBoot.globToPattern "a?.luau"
			assert(string.match("ab.luau", pattern) ~= nil, "expected a value")
			assert(string.match("a.luau", pattern) == nil, "expected no value")
			assert(string.match("a/b.luau", pattern) == nil, "expected no value")
		end)

		suite:case("escapes the Lua pattern metacharacters so a literal dot matches only a dot", function(check)
			local pattern = PlaceBoot.globToPattern "a.luau"
			assert(string.match("a.luau", pattern) ~= nil, "expected a value")
			assert(string.match("axluau", pattern) == nil, "expected no value")
		end)

		suite:case("anchors both ends so a prefix or suffix alone does not match", function(check)
			local pattern = PlaceBoot.globToPattern "main.luau"
			assert(string.match("main.luau", pattern) ~= nil, "expected a value")
			assert(string.match("src/main.luau", pattern) == nil, "expected no value")
			assert(string.match("main.luau.bak", pattern) == nil, "expected no value")
		end)
	end)

	suite:suite("place boot script classes", function()
		suite:case("reads a client suffix as a local script and strips the suffix from the name", function(check)
			local className, base = PlaceBoot.scriptClass "Widget.client.luau"
			check:expect(className):toEqual "LocalScript"
			check:expect(base):toEqual "Widget"
		end)

		suite:case("reads a server suffix as a script and strips the suffix from the name", function(check)
			local className, base = PlaceBoot.scriptClass "Widget.server.luau"
			check:expect(className):toEqual "Script"
			check:expect(base):toEqual "Widget"
		end)

		suite:case("reads a bare luau file as a module script", function(check)
			local className, base = PlaceBoot.scriptClass "Widget.luau"
			check:expect(className):toEqual "ModuleScript"
			check:expect(base):toEqual "Widget"
		end)

		suite:case("refuses a file that is not luau at all", function(check)
			assert(PlaceBoot.scriptClass "Widget.json" == nil, "expected nil")
			assert(PlaceBoot.scriptClass "Widget" == nil, "expected nil")
		end)
	end)

	suite:suite("place boot commit stabilizing", function()
		suite:case("replaces a forty-hex run with the neutral token so a line compares across builds", function(check)
			local sha = string.rep("a", 40)
			check
				:expect((PlaceBoot.stabilizeCommit("built " .. sha .. " ok")))
				:toEqual("built " .. PlaceBoot.COMMIT_TOKEN .. " ok")
		end)

		suite:case("leaves a shorter or longer hex run alone", function(check)
			local short = string.rep("a", 39)
			check:expect((PlaceBoot.stabilizeCommit(short))):toEqual(short)
		end)

		suite:case("replaces every commit on one line, not only the first", function(check)
			local sha = string.rep("b", 40)
			local line = sha .. " and " .. sha
			check
				:expect((PlaceBoot.stabilizeCommit(line)))
				:toEqual(PlaceBoot.COMMIT_TOKEN .. " and " .. PlaceBoot.COMMIT_TOKEN)
		end)
	end)

	suite:suite("place boot alias resolution", function()
		local aliases = { Shared = "shared", Root = "." }

		suite:case("joins a known alias root to the rest of the target", function(check)
			check:expect((PlaceBoot.resolveAlias(aliases, "@Shared/thing/here"))):toEqual "shared/thing/here"
		end)

		suite:case("returns nothing for an alias the consumer never declared", function(check)
			assert(PlaceBoot.resolveAlias(aliases, "@Unknown/thing") == nil, "expected nil")
		end)

		suite:case("returns nothing for a target that is not an alias at all", function(check)
			assert(PlaceBoot.resolveAlias(aliases, "./sibling") == nil, "expected nil")
			assert(PlaceBoot.resolveAlias(aliases, "plain") == nil, "expected nil")
		end)
	end)

	suite:suite("place boot source cache", function()
		suite:case("reads a path once and serves the same text afterwards", function(check)
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
			check:expect(cache.read "a.luau"):toEqual "body"
			check:expect(cache.read "a.luau"):toEqual "body"
			check:expect(reads):toEqual(1)
		end)

		suite:case("compiles a path once and serves the same bytecode afterwards", function(check)
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
			check:expect(cache.bytecode "a.luau"):toEqual "body!"
			check:expect(cache.bytecode "a.luau"):toEqual "body!"
			check:expect(compiles):toEqual(1)
		end)

		suite:case("names the chunk after the path so a failure points at the file", function(check)
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
			check:expect(seen):toEqual "@dir/a.luau"
		end)
	end)

	suite:suite("place boot project tree", function()
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

		suite:case("mounts a directory of scripts and records a source for each one", function(check)
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
			check:expect(#names):toEqual(2)
			check:expect(names[1]):toEqual "Alpha=src/Alpha.server.luau"
			check:expect(names[2]):toEqual "Beta=src/Beta.luau"
		end)

		suite:case("counts only the running scripts, never the module scripts, as scripts to run", function(check)
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
			check:expect(#mounted.scripts):toEqual(2)
		end)

		suite:case("promotes an init file to the folder itself rather than mounting a child", function(check)
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
			assert(container ~= nil, "expected a value")
			check:expect(engine.stateOf(container).className):toEqual "ModuleScript"
			check:expect(engine.stateOf(container).name):toEqual "Mod"
		end)

		suite:case("skips a path the project's ignore globs name", function(check)
			local project =
				[[{"globIgnorePaths":["src/Skip.luau"],"tree":{"ServerScriptService":{"Mod":{"$path":"src"}}}}]]
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
			check:expect(#paths):toEqual(1)
			check:expect(paths[1]):toEqual "src/Keep.luau"
		end)

		suite:case(
			"hands an opaque model path to the consumer's hook and stamps the consumer's attribute",
			function(check)
				local project = [[{"tree":{"ServerScriptService":{"Art":{"$path":"art/thing.rbxm"}}}}]]
				local filled: { string } = {}
				local engine, _mounted = build(project, {}, {}, {
					attribute = "ConsumerUnmounted",
					fill = function(_engine: any, _object: any, path: string)
						filled[#filled + 1] = path
					end,
				})
				check:expect(#filled):toEqual(1)
				check:expect(filled[1]):toEqual "art/thing.rbxm"
				local service = engine.service "ServerScriptService"
				local model = service:FindFirstChild "Art"
				assert(model ~= nil, "expected a value")
				check:expect(engine.attributesOf(model).ConsumerUnmounted):toEqual "art/thing.rbxm"
			end
		)

		suite:case(
			"mounts an opaque model with no attribute and no hook when the consumer declares neither",
			function(check)
				local project = [[{"tree":{"ServerScriptService":{"Art":{"$path":"art/thing.rbxmx"}}}}]]
				local engine, _mounted = build(project, {}, {}, nil)
				local model = engine.service("ServerScriptService"):FindFirstChild "Art"
				assert(model ~= nil, "expected a value")
				check:expect(engine.stateOf(model).className):toEqual "Model"
				assert(next(engine.attributesOf(model)) == nil, "expected nil")
			end
		)

		suite:case("applies a declared property to a mounted node", function(check)
			local project = [[{"tree":{"Workspace":{"Thing":{"$className":"Part","$properties":{"Anchored":true}}}}}]]
			local engine, _mounted = build(project, {}, {}, nil, { Part = { Anchored = "boolean" } })
			local thing = engine.service("Workspace"):FindFirstChild "Thing"
			check:expect(engine.stateOf(thing).values.Anchored):toEqual(true)
		end)

		suite:case("coerces a declared enum property from its string name to the enum item", function(check)
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
			check:expect(engine.stateOf(prompt).values.Style):toEqual "Enum.ProximityPromptStyle.Custom"
		end)

		suite:case("ignores a property the class does not declare", function(check)
			local project = [[{"tree":{"Workspace":{"Thing":{"$className":"Part","$properties":{"Nonsense":1}}}}}]]
			local engine, _mounted = build(project, {}, {}, nil, { Part = { Anchored = "boolean" } })
			local thing = engine.service("Workspace"):FindFirstChild "Thing"
			assert(engine.stateOf(thing).values.Nonsense == nil, "expected nil")
		end)

		suite:case("falls back to a folder when the named path does not exist", function(check)
			local project = [[{"tree":{"ServerScriptService":{"Gone":{"$path":"nowhere"}}}}]]
			local engine, _mounted = build(project, {}, {}, nil)
			local gone = engine.service("ServerScriptService"):FindFirstChild "Gone"
			assert(gone ~= nil, "expected a value")
			check:expect(engine.stateOf(gone).className):toEqual "Folder"
		end)

		suite:case("returns the engine's own root as the mounted root", function(check)
			local project = [[{"tree":{"Workspace":{}}}]]
			local engine, mounted = build(project, {}, {}, nil)
			check:expect(mounted.root):toEqual(engine.game)
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

	local function bootOnce(
		project: string,
		config: any,
		sources: { [string]: string }?,
		directories: { [string]: { { name: string, type: string } } }?
	): (any, any)
		local files = table.clone(sources or {})
		files["p.project.json"] = project
		local engine = bootEngine()
		local sourceHost = host(files)
		sourceHost.compile = luau.compile
		sourceHost.load = function(bytecode: any, chunkName: string, environment: { [string]: any }): any
			return luau.load(bytecode, chunkName, environment)
		end
		local deps: Roblox.PlaceBootDeps = {
			newEngine = function(): any
				return engine
			end,
			cache = PlaceBoot.createCache(sourceHost),
			host = sourceHost,
			files = fileSystem(files, directories or {}),
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

	suite:suite("place boot explicit mounts", function()
		suite:case("requires an explicitly mounted ignored file without discovering it implicitly", function(check)
			local project =
				[[{"globIgnorePaths":["src/Hidden.luau"],"tree":{"ReplicatedStorage":{"Discovered":{"$path":"src"},"Selected":{"$path":"src/Hidden.luau"}}}}]]
			local engine, report = bootOnce(project, {}, {
				["src/Hidden.luau"] = "return { value = 42 }",
			}, { src = { { name = "Hidden.luau", type = "file" } } })
			local storage = engine.service "ReplicatedStorage"
			assert(storage:FindFirstChild("Discovered"):FindFirstChild "Hidden" == nil)
			local selected = storage:FindFirstChild "Selected"
			check:expect(selected.ClassName):toEqual "ModuleScript"
			check:expect(report.mounted.sources[selected]):toEqual "src/Hidden.luau"
			check:expect(report.runtime.requireInstance(selected).value):toEqual(42)
		end)

		suite:case("mounts an explicitly selected ignored directory while retaining descendant ignores", function(check)
			local project =
				[[{"globIgnorePaths":["src/Hidden","src/Hidden/Skip.luau"],"tree":{"ReplicatedStorage":{"Discovered":{"$path":"src"},"Selected":{"$path":"src/Hidden"}}}}]]
			local engine, report = bootOnce(project, {}, {
				["src/Hidden/Keep.luau"] = "return 27",
				["src/Hidden/Skip.luau"] = "return 99",
			}, {
				src = { { name = "Hidden", type = "dir" } },
				["src/Hidden"] = { { name = "Keep.luau", type = "file" }, { name = "Skip.luau", type = "file" } },
			})
			local storage = engine.service "ReplicatedStorage"
			assert(storage:FindFirstChild("Discovered"):FindFirstChild "Hidden" == nil)
			local selected = storage:FindFirstChild "Selected"
			check:expect(selected.ClassName):toEqual "Folder"
			assert(selected:FindFirstChild "Skip" == nil)
			check:expect(report.runtime.requireInstance(selected:FindFirstChild "Keep")):toEqual(27)
		end)

		suite:case("keeps a missing explicit ignored source unrequireable", function(check)
			local project =
				[[{"globIgnorePaths":["src/Missing.luau"],"tree":{"ReplicatedStorage":{"Selected":{"$path":"src/Missing.luau"}}}}]]
			local engine, report = bootOnce(project, {})
			local selected = engine.service("ReplicatedStorage"):FindFirstChild "Selected"
			check:expect(selected.ClassName):toEqual "Folder"
			assert(report.mounted.sources[selected] == nil)
			local ok, failure = pcall(report.runtime.requireInstance, selected)
			check:expect(ok):toEqual(false)
			assert(string.find(tostring(failure), "Attempted to require a Folder", 1, true) ~= nil)
		end)

		suite:case("surfaces invalid source in an explicit ignored module", function(check)
			local project =
				[[{"globIgnorePaths":["src/Hidden.luau"],"tree":{"ReplicatedStorage":{"Selected":{"$path":"src/Hidden.luau"}}}}]]
			local engine, report = bootOnce(project, {}, { ["src/Hidden.luau"] = "return (" })
			local selected = engine.service("ReplicatedStorage"):FindFirstChild "Selected"
			check:expect(selected.ClassName):toEqual "ModuleScript"
			local ok, failure = pcall(report.runtime.requireInstance, selected)
			check:expect(ok):toEqual(false)
			assert(string.find(tostring(failure), "Expected", 1, true) ~= nil)
		end)
	end)

	suite:suite("place boot sequence", function()
		suite:case("reaches every stage once, in the order the sequence declares", function(check)
			local seen: { string } = {}
			local _engine, _report = bootOnce([[{"tree":{"Workspace":{}}}]], {
				observe = function(stage: string)
					seen[#seen + 1] = stage
				end,
			})
			check:expect(#seen):toEqual(6)
			check:expect((table.concat(seen, ","))):toEqual "server,player,client,viewport,character,settled"
		end)

		suite:case("offers no player before one joins and the joined player at every later stage", function(check)
			local withPlayer: { string } = {}
			local _engine, _report = bootOnce([[{"tree":{"Workspace":{}}}]], {
				observe = function(stage: string, view: any)
					if view.player ~= nil and view.playerGui ~= nil then
						withPlayer[#withPlayer + 1] = stage
					end
				end,
			})
			check:expect((table.concat(withPlayer, ","))):toEqual "player,client,viewport,character,settled"
		end)

		suite:case("hands the same engine and runtime to the observer that it reports", function(check)
			local engines: { any } = {}
			local engine, report = bootOnce([[{"tree":{"Workspace":{}}}]], {
				observe = function(_stage: string, view: any)
					engines[#engines + 1] = view.engine
				end,
			})
			check:expect(engines[1]):toEqual(engine)
			check:expect(report.engine):toEqual(engine)
		end)

		suite:case("boots with no observer at all", function(check)
			local _engine, report = bootOnce([[{"tree":{"Workspace":{}}}]], {})
			assert(report.player ~= nil, "expected a player")
			assert(report.playerGui ~= nil, "expected a player gui")
		end)

		suite:case("stamps the injected identity onto the data model", function(check)
			local engine, _report = bootOnce([[{"tree":{"Workspace":{}}}]], {})
			local values = engine.stateOf(engine.game).values
			check:expect(values.GameId):toEqual(7)
			check:expect(values.PlaceId):toEqual(9)
			check:expect(values.PlaceVersion):toEqual(3)
			check:expect(values.JobId):toEqual "job"
		end)

		suite:case("names the witness from the injected name and user id", function(check)
			local engine, report = bootOnce([[{"tree":{"Workspace":{}}}]], {})
			check:expect(engine.stateOf(report.player).values.UserId):toEqual(11)
			check:expect(engine.stateOf(report.player).name):toEqual "Witness"
		end)

		suite:case("stamps the consumer's ready attributes only when it declares them", function(check)
			local engine, _report = bootOnce([[{"tree":{"Workspace":{}}}]], {
				attributes = { character = "Ready", workspace = "Composed" },
			})
			check:expect(engine.attributesOf(engine.service "Workspace").Composed):toEqual(true)
			local bare = select(1, bootOnce([[{"tree":{"Workspace":{}}}]], {}))
			assert(next(bare.attributesOf(bare.service "Workspace")) == nil, "expected no attribute")
		end)

		suite:case("reports the error and warning lines with a commit stabilized, and nothing else", function(check)
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
			check:expect(#report.lines):toEqual(2)
			check:expect(report.lines[1]):toEqual("warn Src: built " .. PlaceBoot.COMMIT_TOKEN)
			check:expect(report.lines[2]):toEqual "error Src: broke"
			assert(engine ~= nil, "expected an engine")
		end)

		suite:case("lets the consumer replace the line stabilizer entirely", function(check)
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
			check:expect(report.lines[1]):toEqual "warn Src: redacted"
		end)
	end)
end
