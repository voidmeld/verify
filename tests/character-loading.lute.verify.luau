--!strict

local Test = require "./harness"
local Lute = require "../src/lute"
local Roblox = require "../src/roblox"
local Environment = require "../src/roblox/environment"

local function fixture(own: (() -> ()) -> ())
	local bridge = Lute.fixture.bridge()
	own(function()
		bridge.close()
	end)
	local engine = bridge.placeEngine()
	local runtime = Roblox.createPlaceRuntime(engine, { root = engine.game, scripts = {}, sources = {} }, {
		aliases = {},
		cache = Roblox.createPlaceCache(Lute.fixture.host),
		host = Lute.fixture.host,
	})
	local player = engine.newInstance("Player", true)
	player.Name, player.Parent = "Witness", engine.service "Players"
	return engine, runtime, player
end

Test.it("loads and replaces a connected player character at its selected spawn", function(own)
	local engine, _, player = fixture(own)
	local spawn = engine.newInstance "SpawnLocation"
	spawn.CFrame = engine.datatypes.CFrame.new(10, 20, 30)
	spawn.Parent, player.RespawnLocation = engine.service "Workspace", spawn
	local events: { string } = {}
	local added = engine.environment.event(player, "CharacterAdded")
	added:Connect(function()
		table.insert(events, "added")
	end)
	engine.environment.event(player, "CharacterRemoving"):Connect(function()
		table.insert(events, "removing")
	end)
	local load = engine.environment.method(player, "LoadCharacterAsync")
	load(player)
	local first = engine.environment.assertInstance(player.Character)
	Test.expect(first.Name):toBe "Witness"
	Test.expect(first.Parent):toBe(engine.service "Workspace")
	Test.expect(first:FindFirstChildOfClass "Humanoid" ~= nil):toBe(true)
	Test.expect(first:FindFirstChild "HumanoidRootPart" ~= nil):toBe(true)
	Test.expect(engine.environment.method(first, "GetPivot")(first)):toEqual(engine.datatypes.CFrame.new(10, 23, 30))
	load(player)
	Test.expect(player.Character == first):toBe(false)
	Test.expect(first.Parent):toBeNil()
	Test.expect(events):toEqual { "added", "removing", "added" }
	player.Parent = nil
	Test.expect(function()
		load(player)
	end):toThrow "character loading requires a connected player"
end)

Test.it("clones the configured starter character and refuses a malformed template", function(own)
	local engine, _, player = fixture(own)
	local template = engine.newInstance "Model"
	template.Name, template.Parent = "StarterCharacter", engine.service "StarterPlayer"
	local root = engine.newInstance "Part"
	root.Name, root.Parent = "HumanoidRootPart", template
	local marker = engine.newInstance "BoolValue"
	marker.Name, marker.Value, marker.Parent = "CustomRig", true, template
	local load = engine.environment.method(player, "LoadCharacterAsync")
	load(player)
	local character = engine.environment.assertInstance(player.Character)
	Test.expect(character == template):toBe(false)
	Test.expect(character:FindFirstChild "CustomRig" ~= nil):toBe(true)
	Test.expect(template.Parent):toBe(engine.service "StarterPlayer")
	root:Destroy()
	Test.expect(function()
		load(player)
	end):toThrow "character requires HumanoidRootPart"
end)

Test.it("place boot preserves a character loaded during player admission", function(own)
	local host = {
		readFile = function(): string
			return '{"tree":{}}'
		end,
		compile = Lute.fixture.host.compile,
		load = Lute.fixture.host.load,
		encodeJson = Lute.fixture.host.encodeJson,
		decodeJson = Lute.fixture.host.decodeJson,
	}
	local loaded: Roblox.Instance? = nil
	local report = Roblox.bootPlace({
		projectPath = "empty.json",
		identity = { universeId = 1, placeId = 2, placeVersion = 3 },
		subject = { name = "Witness", userId = 4, jobId = "test" },
		aliases = {},
		firstViewport = { x = 1, y = 1 },
		finalViewport = { x = 640, y = 480 },
		frames = 1,
		engineProvidedInput = false,
		observe = function(stage, view)
			if stage == "player" then
				local player = assert(view.player)
				view.engine.environment.method(player, "LoadCharacterAsync")(player)
				loaded = view.engine.environment.assertInstance(player.Character)
			end
		end,
	}, {
		newEngine = function()
			local bridge = Lute.fixture.bridge()
			own(function()
				bridge.close()
			end)
			return bridge.placeEngine()
		end,
		host = host,
		cache = Roblox.createPlaceCache(host),
		files = {
			exists = function(): boolean
				return false
			end,
			fileType = function(): string
				return "file"
			end,
			listDirectory = function(): { { name: string, type: string } }
				return {}
			end,
		},
	})
	Test.expect(report.player.Character):toBe(loaded)
	Test.expect(#report.diagnostics):toBe(0)
end)

Test.it("fixed simulation respects cadence, priority, disconnect and disabled worlds", function(own)
	local engine, runtime = fixture(own)
	local run = engine.service "RunService"
	local bind = engine.environment.method(run, "BindToSimulation")
	Test.expect(function()
		bind(run, function() end)
	end):toThrow "requires fixed simulation"
	engine.environment.poke(
		engine.service "Workspace",
		"UseFixedSimulation",
		engine.datatypes.Enum.RolloutState.Enabled
	)
	local events: { string } = {}
	local function callback(name: string): (number) -> ()
		return function(delta: number)
			table.insert(events, name .. ":" .. tostring(math.round(delta * 60)))
		end
	end
	local first = bind(run, callback "late", nil, 20)
	bind(run, callback "early", engine.datatypes.Enum.StepFrequency.Hz30, 10)
	bind(run, callback "fast", engine.datatypes.Enum.StepFrequency.Hz60, 30)
	runtime.step(1 / 30)
	Test.expect(events):toEqual { "fast:1", "early:2", "late:2", "fast:1" }
	assert(type(first) == "table" and type(first.Disconnect) == "function")
	Environment.invoke(first.Disconnect, first)
	table.clear(events)
	runtime.step(1 / 30)
	Test.expect(events):toEqual { "fast:1", "early:2", "fast:1" }
	Test.expect(function()
		bind(run, function() end, engine.datatypes.Enum.KeyCode.A)
	end):toThrow "StepFrequency"
	Test.expect(function()
		bind(run, function() end, nil, 0.5)
	end):toThrow "finite integer"
end)

return nil
