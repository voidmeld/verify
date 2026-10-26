--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Verify = require "../src/core"
local Worker = require "../src/lute/worker"
local Bdd = require "../src/bdd"
local Roblox = require "../src/roblox"
local Example = require "../examples/instance-case"
local Instances = Roblox.instanceHost

describe("reusable instance adapter", function()
	it("runs an unchanged native-ready case against the simulator and releases all instances", function()
		local simulation = Instances.simulated "server"
		local report = Verify.runCase(Example, simulation.host)
		expect(report.passed):toBe(1)
		expect(Verify.decode(report).passed):toBe(1)
		expect(simulation.environment.liveObjects()):toBe(0)
		expect(simulation.environment.liveConnections()):toBe(0)
	end)
	it("worker batches execute the same case with fresh host bindings", function()
		local simulation = Instances.simulated "server"
		local report = Worker.runBatch({
			id = "instances",
			index = 1,
			units = {
				{ id = "instance-case", locator = "instance-case", tags = {}, requires = {}, weight = 1 },
			},
		}, {
			now = simulation.host.now,
			load = function(): unknown
				return function(harness: Verify.Harness)
					harness:case(Example.name, Example)
				end
			end,
		}, {
			executor = "simulated-worker",
			capabilities = simulation.host.capabilities,
			bind = function()
				return simulation.host
			end,
		})
		expect(report.passed):toBe(1)
		expect(report.results[1].source):toBe "instance-case"
		expect(Verify.decode(report).results[1].evidence ~= nil):toBe(true)
		expect(simulation.environment.liveObjects()):toBe(0)
	end)

	it("the session-backed BDD surface binds hosts without a separate runner", function()
		local simulation = Instances.simulated "server"
		local surface = Bdd.surface {
			executor = "simulated-bdd",
			environment = {},
			capabilities = simulation.host.capabilities,
			ambientSource = "instance-case",
			now = simulation.host.now,
			bind = function()
				return simulation.host
			end,
		}
		surface.it(Example.name, {
			id = Example.id,
			requires = Example.requires,
			timeoutSeconds = Example.timeoutSeconds,
			run = function(_own, context)
				Example.run(context)
			end,
		})
		local report = surface.run()
		expect(report.passed):toBe(1)
		expect(report.results[1].evidence ~= nil):toBe(true)
		expect(simulation.environment.liveObjects()):toBe(0)
	end)

	it("a broken write fails the authored case and still releases the fixture", function()
		local simulation = Instances.simulated "server"
		simulation.registry.operations.actions[Instances.setProperty.name] = {
			run = function()
				return nil
			end,
		}
		local report = Verify.runCase(Example, simulation.host)
		expect(report.failed):toBe(1)
		expect(simulation.environment.liveObjects()):toBe(0)
	end)
	it("partial creation failures release the already created object", function()
		local simulation = Instances.simulated "server"
		simulation.environment.failNext "setProperty"
		local report = Verify.runCase(Example, simulation.host)
		expect(report.failed):toBe(1)
		expect(simulation.environment.liveObjects()):toBe(0)
	end)
	it("borrowed descendants survive cleanup and cannot be destroyed by an owned parent", function()
		local env = Roblox.testEnvironment()
		local borrowed = env.createInstance "Folder"
		local bound = Instances.registry {
			actor = "server",
			createInstance = function(name)
				return env.createInstance(name)
			end,
			borrowed = { borrowed = borrowed },
		}
		local function call<I, O>(operation: Verify.Operation<I, O>, input: I): unknown
			return bound.operations.actions[operation.name].run(
				input,
				{ kind = operation.kind, name = operation.name, payload = input, actor = "server", deadline = 5 }
			)
		end
		call(Instances.create, { id = "owned", className = "Folder" })
		call(Instances.parent, { id = "borrowed", parent = "owned" })
		expect(pcall(function()
			call(Instances.destroy, "owned")
		end)):toBe(false)
		bound.close()
		expect(env.isAlive(borrowed)):toBe(true)
		expect(borrowed.Parent):toBe(nil)
		expect(env.liveObjects()):toBe(1)
		borrowed:Destroy()
	end)
end)

return nil
