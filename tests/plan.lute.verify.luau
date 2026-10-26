--!strict

local function asNumber(value: unknown): number
	assert(type(value) == "number")
	return value
end

local Capability = require "../src/core/capability"
local Plan = require "../src/core/plan"
local Batch = require "../src/lute/batch"

local Verify = require "../src/core"

local function unit(id: string, group: string?, tags: { string }?, requires: { string }?): Verify.PlanUnitDraft
	return { id = id, locator = id .. ".verify.luau", group = group, tags = tags, requires = requires }
end

local BASE: Verify.PlanDraft = {
	id = "example",
	units = {
		unit("alpha/one", "alpha", { "neutral" }),
		unit("alpha/two", "alpha", { "neutral" }),
		unit("beta/one", "beta", { "host" }, { "local-luau" }),
		unit("gamma/one", "gamma", { "neutral" }),
		unit("delta/one", nil, { "neutral" }),
	},
}

local function idsOf(units: { Verify.PlanUnit }): { string }
	local ids: { string } = {}
	for _, entry in units do
		table.insert(ids, entry.id)
	end
	return ids
end

local function batchIds(batches: { Verify.PlanBatch }): { { string } }
	local out: { { string } } = {}
	for _, batch in batches do
		table.insert(out, idsOf(batch.units))
	end
	return out
end

return function(suite: Verify.Harness)
	suite:suite("execution plan", function()
		suite:case("normalizes a draft into a versioned plan", function(check)
			local plan = Plan.validate(BASE)
			check:expect(plan.schemaVersion):toEqual(Plan.SCHEMA_VERSION)
			check:expect(plan.policy.maxParallelBatches):toEqual(1)
			check:expect(plan.policy.failFast):toEqual(false)
			check:expect(plan.policy.caseIdStyle):toEqual "unit-prefixed"
			check:expect(plan.policy.retry.maxAttempts):toEqual(1)
			check:expect(plan.units[3].requires):toEqual { "local-luau" }
			check:expect(plan.units[1].tags):toEqual { "neutral" }
		end)

		suite:case("refuses a duplicate unit id and a duplicate locator", function(check)
			local duplicateId = pcall(Plan.validate, {
				id = "p",
				units = { unit "a", { id = "a", locator = "b.verify.luau" } },
			})
			check:expect(duplicateId):toEqual(false)
			local duplicateLocator = pcall(Plan.validate, {
				id = "p",
				units = { unit "a", { id = "b", locator = "a.verify.luau" } },
			})
			check:expect(duplicateLocator):toEqual(false)
		end)

		suite:case("refuses a retry policy that names a correctness outcome", function(check)
			local ok, thrown: unknown = pcall(Plan.validate, {
				id = "p",
				policy = { retry = { maxAttempts = 3, on = { "failed" } } },
				units = { unit "a" },
			})
			check:expect(ok):toEqual(false)
			check:expect((tostring(thrown))):toContain "not an infrastructure outcome"
		end)

		suite:case("refuses more than one attempt with nothing eligible", function(check)
			local ok = pcall(Plan.validate, {
				id = "p",
				policy = { retry = { maxAttempts = 2, on = {} } },
				units = { unit "a" },
			})
			check:expect(ok):toEqual(false)
		end)

		suite:case("selects by id, tag, group and capability without reordering", function(check)
			check:expect((idsOf(Plan.select(BASE, { tags = { "neutral" } }).units))):toEqual {
				"alpha/one",
				"alpha/two",
				"gamma/one",
				"delta/one",
			}
			check
				:expect((idsOf(Plan.select(BASE, { groups = { "alpha" } }).units)))
				:toEqual { "alpha/one", "alpha/two" }
			check:expect((idsOf(Plan.select(BASE, { capabilities = { "local-luau" } }).units))):toEqual { "beta/one" }
			check:expect((idsOf(Plan.select(BASE, { ids = { "gamma/one", "alpha/one" } }).units))):toEqual {
				"alpha/one",
				"gamma/one",
			}
			check:expect(#Plan.select(BASE, nil).units):toEqual(5)
		end)

		suite:case("narrows by predicate over the same selection subject a harness sees", function(check)
			local seen: { Verify.SelectionSubject } = {}
			local selected = Plan.select(BASE, {
				predicate = function(subject: Verify.SelectionSubject): boolean
					table.insert(seen, subject)
					return string.find(assert(subject.source), "alpha", 1, true) ~= nil
				end,
			})
			check:expect((idsOf(selected.units))):toEqual { "alpha/one", "alpha/two" }
			check:expect(#seen):toEqual(5)
			check:expect(seen[1].id):toEqual "alpha/one"
			check:expect(seen[1].source):toEqual "alpha/one.verify.luau"
			check:expect(seen[1].name):toEqual "alpha/one"
			check:expect(seen[1].path):toEqual {}
			check:expect(seen[1].tags):toEqual { "neutral" }
			check:expect(seen[1].requires):toEqual {}
			check
				:expect((idsOf(Plan.select(BASE, {
					groups = { "alpha" },
					predicate = function(subject: Verify.SelectionSubject): boolean
						return subject.id ~= "alpha/two"
					end,
				}).units)))
				:toEqual { "alpha/one" }
		end)

		suite:case("keeps a group whole and partitions the same way every time", function(check)
			local first = batchIds(Plan.partition(BASE, 3))
			local second = batchIds(Plan.partition(BASE, 3))
			check:expect(first):toEqual(second)
			local alphaBatch = nil
			for index, ids in first do
				for _, id in ids do
					if id == "alpha/one" then
						alphaBatch = index
					end
				end
			end
			for index, ids in first do
				for _, id in ids do
					if id == "alpha/two" then
						check:expect(index):toEqual(alphaBatch)
					end
				end
			end
		end)

		suite:case("returns exactly the batch count asked for, empty batches included", function(check)
			local batches = Plan.partition({ id = "p", units = { unit "only" } }, 4)
			check:expect(#batches):toEqual(4)
			check:expect(#batches[1].units):toEqual(1)
			check:expect(#batches[4].units):toEqual(0)
			check:expect(batches[4].id):toEqual "batch-4"
		end)

		suite:case("covers every unit exactly once across batches", function(check)
			local seen: { [string]: number } = {}
			for _, batch in Plan.partition(BASE, 3) do
				for _, id in idsOf(batch.units) do
					seen[id] = (seen[id] or 0) + 1
				end
			end
			for _, entry in Plan.validate(BASE).units do
				check:expect(seen[entry.id]):toEqual(1)
			end
		end)

		suite:case("composes stable case ids in both styles", function(check)
			check
				:expect((Plan.caseId("alpha/one", { "inventory", "release" }, "frees")))
				:toEqual "alpha/one::inventory > release > frees"
			check:expect((Plan.caseId("alpha/one", { "inventory" }, "frees", "bare"))):toEqual "inventory > frees"
			check:expect((pcall(Plan.caseId, "alpha/one", {}, "frees", "invented"))):toEqual(false)
		end)

		suite:case("digests a plan by its meaning and notices every change to it", function(check)
			local base = Plan.digest(BASE)
			check:expect(base):toEqual(Plan.digest(Plan.validate(BASE)))
			local reordered = table.clone(BASE)
			reordered.units = { BASE.units[2], BASE.units[1], BASE.units[3], BASE.units[4], BASE.units[5] }
			assert(Plan.digest(reordered) ~= base)
			local retagged: Verify.PlanDraft = {
				id = "example",
				policy = { failFast = true },
				units = BASE.units,
			}
			assert(Plan.digest(retagged) ~= base)
		end)
	end)

	suite:suite("cost-aware batching", function()
		local WEIGHTED: Verify.PlanDraft = {
			id = "weighted",
			units = {
				{ id = "a", locator = "a.luau", weight = 10 },
				{ id = "b", locator = "b.luau" },
				{ id = "c", locator = "c.luau" },
				{ id = "d", locator = "d.luau" },
				{ id = "e", locator = "e.luau", weight = 10 },
				{ id = "f", locator = "f.luau" },
				{ id = "g", locator = "g.luau" },
				{ id = "h", locator = "h.luau" },
			},
		}

		local function weightOf(batch: Verify.PlanBatch): number
			local total = 0
			for _, unit in batch.units do
				total += unit.weight
			end
			return total
		end

		suite:case("defaults every unit to weight one", function(check)
			local plan = Plan.validate { id = "p", units = { { id = "a", locator = "a.luau" } } }
			check:expect(plan.units[1].weight):toEqual(1)
		end)

		suite:case("refuses a weight that is not a positive number", function(check)
			local function withWeight(weight: unknown): () -> ()
				return function()
					Plan.validate {
						id = "p",
						units = { { id = "a", locator = "a.luau", weight = asNumber(weight) } },
					}
				end
			end
			check:expect((pcall(withWeight(0)))):toEqual(false)
			check:expect((pcall(withWeight(-3)))):toEqual(false)
			check:expect((pcall(withWeight "heavy"))):toEqual(false)
			check:expect((pcall(withWeight(math.huge)))):toEqual(false)
			check:expect((pcall(withWeight(-math.huge)))):toEqual(false)
		end)

		suite:case("balances declared weight instead of unit count", function(check)
			local counted = Plan.partition(WEIGHTED, 4, "count")
			local weighted = Plan.partition(WEIGHTED, 4, "weighted")
			local countedWeights: { number } = {}
			local weightedWeights: { number } = {}
			for index = 1, 4 do
				table.insert(countedWeights, weightOf(counted[index]))
				table.insert(weightedWeights, weightOf(weighted[index]))
			end
			table.sort(countedWeights)
			table.sort(weightedWeights)
			check:expect(countedWeights[4]):toEqual(20)
			check:expect(weightedWeights[4] <= 10):toEqual(true)
			check:expect(countedWeights[4] > weightedWeights[4]):toEqual(true)
			local seen = 0
			for _, batch in weighted do
				seen += #batch.units
			end
			check:expect(seen):toEqual(8)
		end)

		suite:case("is identical to count batching when no weight was declared", function(check)
			local plan: Verify.PlanDraft = {
				id = "unweighted",
				units = {
					{ id = "a", locator = "a.luau" },
					{ id = "b", locator = "b.luau", group = "g" },
					{ id = "c", locator = "c.luau", group = "g" },
					{ id = "d", locator = "d.luau" },
					{ id = "e", locator = "e.luau" },
				},
			}
			for count = 1, 5 do
				local counted = Plan.partition(plan, count, "count")
				local weighted = Plan.partition(plan, count, "weighted")
				for index = 1, count do
					check:expect((idsOf(weighted[index].units))):toEqual(idsOf(counted[index].units))
				end
			end
		end)

		suite:case("keeps a group whole whichever mode partitioned it", function(check)
			local plan: Verify.PlanDraft = {
				id = "grouped",
				units = {
					{ id = "a", locator = "a.luau", group = "shared", weight = 9 },
					{ id = "b", locator = "b.luau", group = "shared", weight = 9 },
					{ id = "c", locator = "c.luau", weight = 1 },
				},
			}
			local weighted = Plan.partition(plan, 3, "weighted")
			for _, batch in weighted do
				local ids = idsOf(batch.units)
				if table.find(ids, "a") ~= nil then
					check:expect(table.find(ids, "b") ~= nil):toEqual(true)
				end
			end
		end)

		suite:case("is a pure function of the plan and never of a timing", function(check)
			local first = Plan.partition(WEIGHTED, 3, "weighted")
			for _ = 1, 10 do
				local again = Plan.partition(WEIGHTED, 3, "weighted")
				for index = 1, 3 do
					check:expect((idsOf(again[index].units))):toEqual(idsOf(first[index].units))
				end
			end
		end)

		suite:case("changes the plan digest when a weight changes", function(check)
			local heavier: Verify.PlanDraft = {
				id = "weighted",
				units = {
					{ id = "a", locator = "a.luau", weight = 11 },
					{ id = "b", locator = "b.luau" },
					{ id = "c", locator = "c.luau" },
					{ id = "d", locator = "d.luau" },
					{ id = "e", locator = "e.luau", weight = 10 },
					{ id = "f", locator = "f.luau" },
					{ id = "g", locator = "g.luau" },
					{ id = "h", locator = "h.luau" },
				},
			}
			check:expect((Plan.digest(WEIGHTED) ~= Plan.digest(heavier))):toEqual(true)
		end)

		suite:case("refuses a batching mode it does not implement", function(check)
			check
				:expect((pcall(function()
					((Plan.partition :: unknown) :: (Verify.PlanDraft, number, string) -> unknown)(
						WEIGHTED,
						2,
						"measured"
					)
				end)))
				:toEqual(false)
		end)

		suite:case("carries declared weight across the worker wire", function(check)
			local batches = Plan.partition(WEIGHTED, 1, "weighted")
			local decoded = Batch.decode(Batch.encode(batches[1]))
			check:expect(decoded.units[1].weight):toEqual(10)
			check:expect(decoded.units[2].weight):toEqual(1)
		end)
	end)

	suite:suite("capability negotiation", function()
		suite:case("names what is missing and what the host declared", function(check)
			local negotiation = Capability.negotiate({ "local-luau", "worker" }, { "worker", "engine-datamodel" })
			check:expect(negotiation.satisfied):toEqual(false)
			check:expect(negotiation.missing):toEqual { "engine-datamodel" }
			check:expect(negotiation.declared):toEqual { "local-luau", "worker" }
			check:expect((Capability.explain(negotiation))):toContain "missing engine-datamodel"
			check:expect((Capability.explain(negotiation))):toContain "the host declared local-luau, worker"
		end)

		suite:case("is satisfied by an empty requirement set and never by an empty declaration", function(check)
			check:expect(Capability.negotiate({}, {}).satisfied):toEqual(true)
			check:expect(Capability.negotiate({}, { "anything" }).satisfied):toEqual(false)
			check:expect((Capability.explain(Capability.negotiate({}, { "anything" })))):toContain "declared none"
		end)

		suite:case("does not depend on the order a host listed its capabilities", function(check)
			local left = Capability.negotiate({ "b", "a" }, { "a" })
			local right = Capability.negotiate({ "a", "b" }, { "a" })
			check:expect(left.declared):toEqual(right.declared)
			check:expect(left.satisfied):toEqual(right.satisfied)
		end)
	end)
end
