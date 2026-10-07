--!strict

local json = require "@std/json"

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

return function(suite: Verify.Harness)
	suite:suite("verify execution hosts", function()
		suite:case("runs a batch in a real worker and composes what it wrote", function(check)
			local plan: Verify.PlanDraft = {
				id = "worker-example",
				units = { { id = "bdd", locator = "examples/bdd.verify.luau" } },
			}
			local execution = Verify.execute(plan, Lute.host { worker = "examples/worker.luau" })
			check:expect(execution.report.executor):toEqual "lute"
			check:expect(execution.report.passed):toEqual(1)
			check:expect(execution.report.skipped):toEqual(1)
			check:expect(execution.report.failed):toEqual(0)
			check:expect(execution.attempts[1].status):toEqual "returned"
			check:expect(execution.report.environment["verify.plan"]):toEqual "worker-example"
		end)

		suite:case("names a unit the worker could not load without failing the batch", function(check)
			local plan: Verify.PlanDraft = {
				id = "worker-missing",
				units = {
					{ id = "bdd", locator = "examples/bdd.verify.luau" },
					{ id = "absent", locator = "examples/does-not-exist.verify.luau" },
				},
			}
			local execution = Verify.execute(plan, Lute.host { worker = "examples/worker.luau" }, { batchCount = 1 })
			check:expect(execution.attempts[1].status):toEqual "returned"
			check:expect(execution.report.passed):toEqual(1)
			check:expect(execution.report.failed):toEqual(1)
			assert(statusOfCase(execution.report, "unit:absent:load") == "failed")
		end)

		suite:case("faults rather than failing when the worker itself cannot start", function(check)
			local plan: Verify.PlanDraft = {
				id = "worker-absent",
				units = { { id = "bdd", locator = "examples/bdd.verify.luau" } },
			}
			local execution = Verify.execute(plan, Lute.host { worker = "examples/no-such-worker.luau" })
			check:expect(execution.attempts[1].status):toEqual "faulted"
			check:expect(execution.report.failed):toEqual(1)
			check:expect((tostring(execution.attempts[1].detail))):toContain "wrote no report"
		end)

		suite:case("rejects incorrectly typed batch wire fields", function(check)
			for _, field in { "group", "deadlineSeconds" } do
				local unit: { [string]: unknown } = { id = "a", locator = "a.verify.luau" }
				unit[field] = false
				local encoded = json.serialize { wireVersion = 1, id = "wire", index = 1, units = { unit } }
				check:expect((pcall(Lute.decodeBatch, encoded))):toEqual(false)
			end
			for _, encoded in
				{
					'{"wireVersion":1,"id":"wire","index":1,"units":false}',
					'{"wireVersion":1,"id":"wire","index":1,"units":[],"deadlineSeconds":false}',
				}
			do
				check:expect((pcall(Lute.decodeBatch, encoded))):toEqual(false)
			end
		end)

		suite:case("round-trips a batch across the worker wire", function(check)
			local batches = Verify.partitionPlan({
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
			local decoded = Lute.decodeBatch(Lute.encodeBatch(batches[1]))
			check:expect(decoded.id):toEqual(batches[1].id)
			check:expect(decoded.index):toEqual(1)
			check:expect(#decoded.units):toEqual(2)
			check:expect(decoded.units[1].requires):toEqual { "local-luau" }
			check:expect(decoded.units[2].group):toEqual "g"
			check:expect((pcall(Lute.decodeBatch, "{}"))):toEqual(false)
		end)
	end)
end
