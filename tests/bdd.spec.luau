--!strict

local test = require "@std/test"

local Bdd = require "../src/bdd"
local Verify = require "../src/core"

test.suite("BDD authoring", function(suite)
	suite:case("preserves familiar authoring while delegating lifecycle to Verify", function(assert)
		local tick = 0
		local harness = Verify.createHarness {
			now = function()
				tick += 0.001
				return tick
			end,
		}
		local bdd = Bdd.create(harness)
		local trace: { string } = {}
		bdd.describe("suite", function()
			bdd.beforeEach(function(own)
				table.insert(trace, "setup")
				own(function()
					table.insert(trace, "cleanup")
				end)
			end)
			bdd.it("case", function()
				bdd.expect(2 + 2):toBe(4)
				table.insert(trace, "case")
			end)
			bdd.afterEach(function()
				table.insert(trace, "teardown")
			end)
		end)
		local report = harness:run { executor = "test" }
		assert.eq(report.passed, 1)
		assert.eq(trace, { "setup", "case", "teardown", "cleanup" })
	end)

	suite:case("hands a spy through alongside the authoring verbs", function(assert)
		local harness = Verify.createHarness { now = os.clock }
		local bdd = Bdd.create(harness)
		bdd.it("case", function()
			local collaborator = bdd.spy(function(name: string): string
				return "greeted " .. name
			end)
			bdd.expect(collaborator.fn "warder"):toBe "greeted warder"
			bdd.expect(collaborator.callCount()):toBe(1)
			bdd.expect(collaborator.lastArgs()):toEqual { "warder" }
		end)
		local report = harness:run { executor = "test" }
		assert.eq(report.passed, 1)
		assert.eq(report.failed, 0)
	end)

	suite:case("routes runtime and declared skips through Verify", function(assert)
		local harness = Verify.createHarness { now = os.clock }
		local bdd = Bdd.create(harness)
		bdd.itSkip("declared", "not selected")
		bdd.it("runtime", function()
			bdd.skip "executor declined"
		end)
		local report = harness:run { executor = "test" }
		assert.eq(report.skipped, 2)
	end)
end)
