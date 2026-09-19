--!strict

local test = require "@std/test"
local Verify = require "../src/core"
local Lute = require "../src/lute"

local function statusOfCase(report: Verify.Report, id: string): string?
	for _, result in report.results do
		if result.id == id then
			return result.status
		end
	end
	return nil
end

test.suite("verify execution hosts", function(suite)
	suite:case("runs a batch in a real worker and composes what it wrote", function(assert)
		local plan: Verify.PlanDraft = {
			id = "worker-example",
			units = { { id = "bdd", locator = "examples/bdd.verify.luau" } },
		}
		local execution = Verify.execute(plan, Lute.host { worker = "examples/worker.luau" })
		assert.eq(execution.report.executor, "lute")
		assert.eq(execution.report.passed, 1)
		assert.eq(execution.report.skipped, 1)
		assert.eq(execution.report.failed, 0)
		assert.eq(execution.attempts[1].status, "returned")
		assert.eq(execution.report.environment["verify.plan"], "worker-example")
	end)

	suite:case("names a unit the worker could not load without failing the batch", function(assert)
		local plan: Verify.PlanDraft = {
			id = "worker-missing",
			units = {
				{ id = "bdd", locator = "examples/bdd.verify.luau" },
				{ id = "absent", locator = "examples/does-not-exist.verify.luau" },
			},
		}
		local execution = Verify.execute(plan, Lute.host { worker = "examples/worker.luau" }, { batchCount = 1 })
		assert.eq(execution.attempts[1].status, "returned")
		assert.eq(execution.report.passed, 1)
		assert.eq(execution.report.failed, 1)
		assert.that(statusOfCase(execution.report, "unit:absent:load") == "failed")
	end)

	suite:case("faults rather than failing when the worker itself cannot start", function(assert)
		local plan: Verify.PlanDraft = {
			id = "worker-absent",
			units = { { id = "bdd", locator = "examples/bdd.verify.luau" } },
		}
		local execution = Verify.execute(plan, Lute.host { worker = "examples/no-such-worker.luau" })
		assert.eq(execution.attempts[1].status, "faulted")
		assert.eq(execution.report.failed, 1)
		assert.strContains(tostring(execution.attempts[1].detail), "wrote no report")
	end)

	suite:case("round-trips a batch across the worker wire", function(assert)
		local batches = Verify.partitionPlan({
			id = "wire",
			units = {
				{ id = "a", locator = "a.verify.luau", group = "g", tags = { "neutral" }, requires = { "local-luau" } },
				{ id = "b", locator = "b.verify.luau", group = "g" },
			},
		}, 1)
		local decoded = Lute.decodeBatch(Lute.encodeBatch(batches[1]))
		assert.eq(decoded.id, batches[1].id)
		assert.eq(decoded.index, 1)
		assert.eq(#decoded.units, 2)
		assert.eq(decoded.units[1].requires, { "local-luau" })
		assert.eq(decoded.units[2].group, "g")
		assert.eq(pcall(Lute.decodeBatch, "{}"), false)
	end)
end)
