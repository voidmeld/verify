--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Plan = require "../src/core/plan"
local json = require "@std/json"

local Verify = require "../src/core"
local Batch = require "../src/lute/batch"
local Lute = require "../src/lute"

local function statusOfCase(report: Verify.Report, id: string): string?
	for _, result in report.results do
		if result.id == id then
			return result.status
		end
	end
	return nil
end

describe("verify execution hosts", function()
	it("runs a batch in a real worker and composes what it wrote", function()
		local plan: Verify.PlanDraft = {
			id = "worker-example",
			units = { { id = "bdd", locator = "examples/bdd.verify.luau" } },
		}
		local execution = Verify.execute(plan, Lute.host { worker = "examples/worker.luau" })
		expect(execution.report.executor):toEqual "lute"
		expect(execution.report.passed):toEqual(1)
		expect(execution.report.skipped):toEqual(1)
		expect(execution.report.failed):toEqual(0)
		expect(execution.attempts[1].status):toEqual "returned"
		expect(execution.report.environment["verify.plan"]):toEqual "worker-example"
	end)

	it("names a unit the worker could not load without failing the batch", function()
		local plan: Verify.PlanDraft = {
			id = "worker-missing",
			units = {
				{ id = "bdd", locator = "examples/bdd.verify.luau" },
				{ id = "absent", locator = "examples/does-not-exist.verify.luau" },
			},
		}
		local execution = Verify.execute(plan, Lute.host { worker = "examples/worker.luau" }, { batchCount = 1 })
		expect(execution.attempts[1].status):toEqual "returned"
		expect(execution.report.passed):toEqual(1)
		expect(execution.report.failed):toEqual(1)
		assert(statusOfCase(execution.report, "unit:absent:load") == "failed")
	end)

	it("faults rather than failing when the worker itself cannot start", function()
		local plan: Verify.PlanDraft = {
			id = "worker-absent",
			units = { { id = "bdd", locator = "examples/bdd.verify.luau" } },
		}
		local execution = Verify.execute(plan, Lute.host { worker = "examples/no-such-worker.luau" })
		expect(execution.attempts[1].status):toEqual "faulted"
		expect(execution.report.failed):toEqual(1)
		expect((tostring(execution.attempts[1].detail))):toContain "wrote no report"
	end)

	it("rejects incorrectly typed batch wire fields", function()
		for _, field in { "group", "deadlineSeconds" } do
			local unit: { [string]: unknown } = { id = "a", locator = "a.verify.luau" }
			unit[field] = false
			local encoded = json.serialize { wireVersion = 1, id = "wire", index = 1, units = { unit } }
			expect((pcall(Lute.decodeBatch, encoded))):toEqual(false)
		end
		for _, encoded in
			{
				'{"wireVersion":1,"id":"wire","index":1,"units":false}',
				'{"wireVersion":1,"id":"wire","index":1,"units":[],"deadlineSeconds":false}',
			}
		do
			expect((pcall(Lute.decodeBatch, encoded))):toEqual(false)
		end
	end)

	it("round-trips a batch across the worker wire", function()
		local batches = Plan.partition({
			id = "wire",
			units = {
				{
					id = "a",
					locator = "a.verify.luau",
					group = "g",
					tags = { "neutral" },
					requires = { "local-luau" },
				},
				{ id = "b", locator = "b.verify.luau", group = "g" },
			},
		}, 1)
		local decoded = Batch.decode(Batch.encode(batches[1]))
		expect(decoded.id):toEqual(batches[1].id)
		expect(decoded.index):toEqual(1)
		expect(#decoded.units):toEqual(2)
		expect(decoded.units[1].requires):toEqual { "local-luau" }
		expect(decoded.units[2].group):toEqual "g"
		expect((pcall(Lute.decodeBatch, "{}"))):toEqual(false)
	end)
end)

return nil
