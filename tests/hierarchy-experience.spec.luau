--!strict

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

return function(suite: Verify.Harness)
	suite:suite("hierarchy experience example", function()
		suite:case("the exported case checks the simulator through its ordinary Instance surface", function(check)
			local host, environment = fixture()
			local result = Verify.runCase(Example.case, host)
			check:expect(result.passed):toEqual(1)
			check:expect(#(result.results[1].evidence :: Experience.Evidence).observations):toEqual(11)
			check:expect(environment.liveObjects()):toEqual(0)
			check:expect(environment.liveConnections()):toEqual(0)
			assert(host.close ~= nil)
			host.close()
			check:expect(environment.liveObjects()):toEqual(0)
		end)

		suite:case("independent hosts produce comparable observations from the same case", function(check)
			local first = fixture()
			local second = fixture()
			local left = Verify.runCase(Example.case, first)
			local right = Verify.runCase(Example.case, second)
			check:expect(Verify.observationParity(left, right).status):toEqual "passed"
		end)

		suite:case("a broken reparent operation fails the shared case and still disposes its folders", function(check)
			local host, environment = fixture()
			local invoke = host.invoke
			host.invoke = function(request: Experience.Request): unknown
				if request.kind == "action" then
					return nil
				end
				return invoke(request)
			end
			local result = Verify.runCase(Example.case, host)
			check:expect(result.failed):toEqual(1)
			check:expect(environment.liveObjects()):toEqual(0)
			check:expect(environment.liveConnections()):toEqual(0)
		end)

		suite:case("a failed fixture setup disposes every folder already created", function(check)
			local host, environment = fixture()
			environment.failNext "setProperty"
			local result = Verify.runCase(Example.case, host)
			check:expect(result.failed):toEqual(1)
			check:expect(environment.liveObjects()):toEqual(0)
		end)
	end)
end
