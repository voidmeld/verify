--!strict

local load = require :: (string) -> unknown
local process = load "@lune/process" :: { exit: (number?) -> () }

local Environment = require "../src/roblox/environment"
local LuneReflection = require "../src/lune/reflection"
local UiFakes = require "../src/roblox/ui-fakes"
local Verify = require "../src/core"

local roblox = load "@lune/roblox" :: LuneReflection.Native<unknown, unknown, unknown, unknown, unknown, unknown> & {
	Enum: { Material: { Plastic: unknown }, KeyCode: { A: unknown } },
}

local clock = 0
local harness = Verify.createHarness {
	now = function(): number
		clock += 0.001
		return clock
	end,
}

local function rejects(body: () -> unknown): boolean
	return not pcall(body)
end

harness:suite("simulated instances over the native class database", function()
	harness:case("accepts native datatypes and refuses mismatched ones", function(context)
		local bridge = LuneReflection.create()
		local label = bridge.environment.createInstance "TextLabel"
		label.Size = roblox.UDim2.new(0, 120, 0, 24)
		context:expect(typeof(label.Size)):toBe "UDim2"
		context
			:expect(rejects(function(): unknown
				label.Size = roblox.Vector3.new(1, 2, 3)
				return nil
			end))
			:toBe(true)
		context
			:expect(rejects(function(): unknown
				label.Text = 5
				return nil
			end))
			:toBe(true)
	end)

	harness:case("restricts focus to visible controls and releases it on close", function(context)
		local bridge = LuneReflection.create()
		local env = bridge.environment
		local hidden = env.createInstance("Frame", { Visible = false })
		local box = env.createInstance("TextBox", { Parent = hidden })
		local focus = box.CaptureFocus :: Environment.Method
		context
			:expect(rejects(function(): unknown
				return focus(box)
			end))
			:toBe(true)
		hidden.Visible = true
		focus(box)
		context:expect((bridge.ui :: UiFakes.Controller).focused() == box):toBe(true)
		context:expect(bridge.close().connections):toBe(0)
	end)

	harness:case("refuses an injected failure that never fired", function(context)
		local bridge = LuneReflection.create()
		bridge.faults.inject("create", 1)
		context:expect(rejects(bridge.faults.assertConsumed)):toBe(true)
		context
			:expect(rejects(function(): unknown
				return bridge.environment.createInstance "Folder"
			end))
			:toBe(true)
		bridge.faults.assertConsumed()
	end)
end)

local report = harness:run {
	executor = "lune-fixture-example",
	capabilities = {},
	environment = { runtime = "lune", engine = "simulated" },
}
print(Verify.format(report))
if report.total == 0 or report.passed ~= report.total then
	process.exit(1)
end
