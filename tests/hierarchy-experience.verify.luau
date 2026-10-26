--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Verify = require "../src/core"
local Experience = require "../src/core/operations"
local Environment = require "../src/roblox/environment"
local Example = require "../examples/hierarchy-experience"

local function fixture(): (Experience.Host, Environment.Environment)
	local environment = Environment.create()
	local host = Example.host(function(): Example.Folder
		return ((environment.createInstance "Folder") :: unknown) :: Example.Folder
	end, { name = "simulated-hierarchy", environment = { runtime = "simulation" }, now = environment.now })
	return host, environment
end

describe("hierarchy experience example", function()
	it("the exported case checks the simulator through its ordinary Instance surface", function()
		local host, environment = fixture()
		local result = Verify.runCase(Example.case, host)
		expect(result.passed):toEqual(1)
		expect(#(assert(result.results[1].evidence)).observations):toEqual(11)
		expect(environment.liveObjects()):toEqual(0)
		expect(environment.liveConnections()):toEqual(0)
		assert(host.close ~= nil)
		host.close()
		expect(environment.liveObjects()):toEqual(0)
	end)

	it("independent hosts produce comparable observations from the same case", function()
		local first = fixture()
		local second = fixture()
		local left = Verify.runCase(Example.case, first)
		local right = Verify.runCase(Example.case, second)
		expect(Verify.observationParity(left, right).status):toEqual "passed"
	end)

	it("a broken reparent operation fails the shared case and still disposes its folders", function()
		local host, environment = fixture()
		local invoke = host.invoke
		host.invoke = function(request: Experience.Request): unknown
			if request.kind == "action" then
				return nil
			end
			return invoke(request)
		end
		local result = Verify.runCase(Example.case, host)
		expect(result.failed):toEqual(1)
		expect(environment.liveObjects()):toEqual(0)
		expect(environment.liveConnections()):toEqual(0)
	end)

	it("a failed fixture setup disposes every folder already created", function()
		local host, environment = fixture()
		environment.failNext "setProperty"
		local result = Verify.runCase(Example.case, host)
		expect(result.failed):toEqual(1)
		expect(environment.liveObjects()):toEqual(0)
	end)
end)

return nil
