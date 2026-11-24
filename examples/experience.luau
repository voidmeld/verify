--!strict

local Verify = require "../src/core"
local Experience = require "../src/core/operations"

local function nothing(value: unknown): nil
	assert(value == nil, "expected no payload")
	return nil
end
local increment = Verify.operation {
	kind = "action",
	name = "increment",
	input = nothing,
	output = function(value: unknown): unknown
		return value
	end,
}
local countQuery = Verify.operation {
	kind = "query",
	name = "count",
	input = nothing,
	output = function(value: unknown): number
		assert(type(value) == "number", "expected count")
		return value
	end,
}

local counter = 0
local host: Experience.Host = {
	name = "integration",
	capabilities = { "action:increment", "query:count" },
	environment = { runtime = "in-memory", fidelity = "application logic only" },
	now = os.clock,
	invoke = function(request)
		assert(request.actor == "server", "unknown actor")
		if request.kind == "action" and request.name == "increment" then
			counter += 1
			return nil
		end
		assert(request.kind == "query" and request.name == "count", "unsupported operation")
		return counter
	end,
}
local result = Verify.runCase({
	id = "counter",
	name = "increment is observable",
	requires = { "action:increment", "query:count" },
	timeoutSeconds = 2,
	run = function(context: Verify.Context)
		context:perform("server", increment, nil)
		context:expect(context:perform("server", countQuery, nil)):toBe(1)
	end,
}, host)
print(Verify.format(result))
assert(result.passed == 1)
