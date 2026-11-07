--!strict

local Test = require "./harness"
local Lute = require "../src/lute"
local Roblox = require "../src/roblox"

local function fixture(own: (() -> ()) -> ())
	local bridge = Lute.fixture.bridge()
	own(bridge.close)
	local engine = bridge.placeEngine()
	local env = engine.environment
	local player = engine.newInstance("Player", true)
	local character = engine.newInstance "Model"
	character.Parent = engine.service "Workspace"
	local root = engine.newInstance "Part"
	root.Name, root.Parent = "HumanoidRootPart", character
	root.Position = engine.datatypes.Vector3.zero
	player.Character = character
	local part = engine.newInstance "Part"
	part.Parent = engine.service "Workspace"
	part.Position = engine.datatypes.Vector3.new(5, 0, 0)
	local prompt = engine.newInstance "ProximityPrompt"
	prompt.Enabled, prompt.MaxActivationDistance, prompt.HoldDuration = true, 10, 0.5
	prompt.KeyboardKeyCode = engine.datatypes.Enum.KeyCode.E
	prompt.Parent = part
	local visible = true
	local host = Roblox.promptHost.simulated(engine, {
		player = player,
		visible = function()
			return visible
		end,
	})
	own(function()
		host:Disconnect()
	end)
	local events: { string } = {}
	for _, event in
		{ "PromptShown", "PromptHidden", "PromptButtonHoldBegan", "PromptButtonHoldEnded", "Triggered", "TriggerEnded" }
	do
		env.event(prompt, event):Connect(function()
			table.insert(events, event)
		end)
	end
	local function step(seconds: number)
		env.scheduler.advance(seconds)
		env.scheduler.drain(100)
		env.fire(engine.service "RunService", "Heartbeat", seconds)
	end
	return {
		engine = engine,
		env = env,
		player = player,
		prompt = prompt,
		part = part,
		root = root,
		host = host,
		events = events,
		step = step,
		visible = function(value: boolean)
			visible = value
		end,
	}
end

Test.it("configured prompt visibility respects distance, service state and host visibility", function(own)
	local f = fixture(own)
	Test.expect(f.engine.service("ProximityPromptService").Enabled):toBe(true)
	f.step(0)
	Test.expect(f.events):toEqual { "PromptShown" }
	f.root.Position = f.engine.datatypes.Vector3.new(30, 0, 0)
	f.step(0)
	Test.expect(f.events):toEqual { "PromptShown", "PromptHidden" }
	f.root.Position = f.engine.datatypes.Vector3.zero
	f.visible(false)
	f.step(0)
	Test.expect(#f.events):toBe(2)
	f.visible(true)
	f.engine.service("ProximityPromptService").Enabled = false
	f.step(0)
	Test.expect(#f.events):toBe(2)
	f.engine.service("ProximityPromptService").Enabled = true
	f.step(0)
	Test.expect(#f.events):toBe(3)
	f.prompt.Enabled = false
	f.step(0)
	Test.expect(f.events[4]):toBe "PromptHidden"
end)

Test.it("prompt holds cancel early and trigger once only after their duration", function(own)
	local f = fixture(own)
	local triggered = 0
	f.env.event(f.engine.service "ProximityPromptService", "PromptTriggered"):Connect(function(prompt, player)
		Test.expect(prompt):toBe(f.prompt)
		Test.expect(player):toBe(f.player)
		triggered += 1
	end)
	local begin = f.env.method(f.prompt, "InputHoldBegin")
	local finish = f.env.method(f.prompt, "InputHoldEnd")
	begin(f.prompt)
	f.step(0.2)
	finish(f.prompt)
	f.step(0.4)
	Test.expect(triggered):toBe(0)
	begin(f.prompt)
	f.step(0.49)
	Test.expect(triggered):toBe(0)
	f.step(0.02)
	Test.expect(triggered):toBe(1)
	f.step(1)
	Test.expect(triggered):toBe(1)
	finish(f.prompt)
	Test.expect(f.events[#f.events]):toBe "TriggerEnded"
	begin(f.prompt)
	f.host:Disconnect()
	f.step(1)
	Test.expect(triggered):toBe(1)
end)

Test.it("public keys activate zero-duration prompts and removal cancels a pending hold", function(own)
	local f = fixture(own)
	local input = { KeyCode = f.engine.datatypes.Enum.KeyCode.E }
	local service = f.engine.service "UserInputService"
	f.prompt.HoldDuration = 0
	f.env.fire(service, "InputBegan", input, true)
	f.step(0)
	Test.expect(table.find(f.events, "Triggered")):toBe(nil)
	f.env.fire(service, "InputBegan", input, false)
	f.step(0)
	Test.expect(f.events):toEqual { "PromptShown", "Triggered" }
	f.env.fire(service, "InputEnded", input, false)
	Test.expect(f.events[#f.events]):toBe "TriggerEnded"
	f.prompt.HoldDuration = 1
	f.env.fire(service, "InputBegan", input, false)
	f.prompt.Parent = nil
	f.step(0.1)
	f.step(2)
	local count = 0
	for _, event in f.events do
		if event == "Triggered" then
			count += 1
		end
	end
	Test.expect(count):toBe(1)
	Test.expect(f.events[#f.events]):toBe "PromptHidden"
end)

return nil
