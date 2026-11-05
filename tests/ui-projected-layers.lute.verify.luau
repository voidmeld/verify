--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Roblox = require "../src/roblox"
local Lute = require "../src/lute"
local Types = require "../src/roblox/datatypes"

it("projected layers and text agree with native geometry across camera distances and culling", function(own)
	local roots: { Roblox.Instance } = {}
	local bridge = Lute.fixture.bridge(nil, {
		layout = {
			roots = function()
				return roots
			end,
			viewport = function()
				return { X = 800, Y = 600 }
			end,
		},
	})
	own(bridge.close)
	local engine = bridge.placeEngine()
	local runtime = Roblox.createPlaceRuntime(engine, { root = engine.game, scripts = {}, sources = {} }, {
		aliases = {},
		cache = Roblox.createPlaceCache(Lute.fixture.host),
		host = Lute.fixture.host,
		client = { name = "Projection", userId = 1, viewport = { x = 800, y = 600 } },
		beforeRender = assert(bridge.layout).step,
	})
	own(function()
		for index = #runtime.closeHandlers, 1, -1 do
			runtime.closeHandlers[index]()
		end
	end)
	table.insert(roots, assert(assert(runtime.localPlayer):FindFirstChild "PlayerGui"))
	table.insert(roots, engine.service "Workspace")
	local complete = false
	local scheduler = bridge.environment.scheduler
	local thread = scheduler.spawnTagged({ context = "client", source = "ui-projected-layers" }, function()
		complete = Lute.chunk.load(require "./fixtures/ui-projected-layers", { environment = runtime.globals })()
			== true
	end)
	own(function()
		scheduler.cancel(thread)
	end)
	for _ = 1, 600 do
		if complete or #scheduler.failures > 0 then
			break
		end
		local ok, message = pcall(runtime.step, 1 / 60)
		expect(if ok then "" else tostring(message)):toBe ""
	end
	expect(scheduler.failures):toEqual {}
	expect(engine.diagnostics):toEqual {}
	expect(complete):toBe(true)
end)

it("missing camera and adornee data refuse before publishing any root geometry", function(own)
	for _, missing in
		{
			"CurrentCamera",
			"Adornee or parent part",
			"adornee position and bounds",
			"SizeOffset",
			"valid camera projection",
		}
	do
		local roots: { Roblox.Instance } = {}
		local environment: Roblox.Environment? = nil
		local bridge = Lute.fixture.bridge(nil, {
			layout = {
				roots = function()
					return roots
				end,
				viewport = function()
					return { X = 800, Y = 600 }
				end,
				read = function(object, property)
					if missing == "SizeOffset" and property == "SizeOffset" then
						return nil
					end
					return assert(environment).propertyOf(object, property)
				end,
			},
		})
		own(bridge.close)
		local engine = bridge.placeEngine()
		local env = bridge.environment
		environment = env
		local screen = env.createInstance "ScreenGui"
		local bill = env.createInstance("BillboardGui", {
			Size = Types.UDim2.fromOffset(200, 100),
			Adornee = if missing == "adornee position and bounds"
				then env.createInstance "Folder"
				else env.createInstance "Part",
		})
		if missing == "Adornee or parent part" then
			bill.Adornee = nil
		end
		if missing ~= "CurrentCamera" then
			local camera = env.createInstance "Camera"
			env.poke(camera, "ViewportSize", Types.Vector2.new(800, 600))
			if missing == "valid camera projection" then
				env.poke(camera, "ViewportSize", Types.Vector2.zero)
			end
			env.poke(engine.service "Workspace", "CurrentCamera", camera)
		end
		table.insert(roots, screen)
		table.insert(roots, bill)
		env.poke(screen, "AbsoluteSize", Types.Vector2.new(17, 19))
		local ok, message = pcall(assert(bridge.layout).step)
		expect(ok):toBe(false)
		expect(tostring(message)):toContain "unsupported_ui_layout"
		expect(tostring(message)):toContain(missing)
		expect(env.propertyOf(screen, "AbsoluteSize")):toEqual(Types.Vector2.new(17, 19))
	end
end)

it("host projection revisions invalidate mounted geometry without instance mutations", function(own)
	local roots: { Roblox.Instance } = {}
	local revision, distance = 0, 20
	local projection: Roblox.UiProjectionHost = {
		revision = function()
			return revision
		end,
		camera = function()
			return {
				basis = {
					position = { X = 0, Y = 0, Z = distance },
					right = { X = 1, Y = 0, Z = 0 },
					up = { X = 0, Y = 1, Z = 0 },
					back = { X = 0, Y = 0, Z = 1 },
				},
				viewport = { X = 800, Y = 600 },
				fieldOfView = 70,
			}
		end,
		adornee = function()
			return {
				basis = {
					position = { X = 0, Y = 0, Z = 0 },
					right = { X = 1, Y = 0, Z = 0 },
					up = { X = 0, Y = 1, Z = 0 },
					back = { X = 0, Y = 0, Z = 1 },
				},
				size = { X = 4, Y = 6, Z = 2 },
			}
		end,
	}
	local bridge = Lute.fixture.bridge(nil, {
		layout = {
			roots = function()
				return roots
			end,
			viewport = function()
				return { X = 800, Y = 600 }
			end,
			projection = projection,
		},
	})
	own(bridge.close)
	local env = bridge.environment
	local mount = env.createInstance "Folder"
	local bill = env.createInstance("BillboardGui", {
		Parent = mount,
		Adornee = env.createInstance "Part",
		Size = Types.UDim2.new(4, 20, 2, 10),
	})
	local child = env.createInstance("Frame", { Parent = bill, Size = Types.UDim2.fromScale(1, 1) })
	table.insert(roots, mount)
	expect(child.AbsoluteSize):toEqual(Types.Vector2.new(106, 53))
	distance, revision = 40, 1
	expect(child.AbsoluteSize):toEqual(Types.Vector2.new(63, 31))
	distance, revision = 20, 2
	assert(bridge.layout).step()
	expect(child.AbsoluteSize):toEqual(Types.Vector2.new(106, 53))
end)

return nil
