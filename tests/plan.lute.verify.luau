--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Capability = require "../src/core/capability"
local Plan = require "../src/core/plan"
local Chunk = require "../src/lute/chunk"
local Batch = require "../src/lute/batch"

local Verify = require "../src/core"

local function validate(draft: Verify.PlanDraft): Verify.Plan
	return Plan.validate(draft)
end
local function partition(draft: Verify.PlanDraft, count: number): { Verify.PlanBatch }
	return Plan.partition(draft, count)
end
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

describe("execution plan", function()
	it("normalizes a draft into a versioned plan", function()
		local plan = Plan.validate(BASE)
		expect(plan.schemaVersion):toEqual(Plan.SCHEMA_VERSION)
		expect(plan.policy.maxParallelBatches):toEqual(1)
		expect(plan.policy.failFast):toEqual(false)
		expect(plan.policy.caseIdStyle):toEqual "unit-prefixed"
		expect(plan.policy.retry.maxAttempts):toEqual(1)
		expect(plan.units[3].requires):toEqual { "local-luau" }
		expect(plan.units[1].tags):toEqual { "neutral" }
	end)

	it("selects and partitions a validated plan without changing its policy or digest", function()
		local plan = Plan.validate(BASE)
		local digest = Plan.digest(plan)
		local selected = Plan.select(plan, { groups = { "alpha" } })
		expect(idsOf(selected.units)):toEqual { "alpha/one", "alpha/two" }
		expect(selected.policy):toEqual(plan.policy)
		local batches = Plan.partition(selected, 2)
		expect(batchIds(batches)):toEqual { { "alpha/one", "alpha/two" }, {} }
		expect(Plan.digest(plan)):toEqual(digest)
	end)

	it("refuses a duplicate unit id and a duplicate locator", function()
		local duplicateId = pcall(function()
			return validate {
				id = "p",
				units = { unit "a", { id = "a", locator = "b.verify.luau" } },
			}
		end)
		expect(duplicateId):toEqual(false)
		local duplicateLocator = pcall(function()
			return validate {
				id = "p",
				units = { unit "a", { id = "b", locator = "a.verify.luau" } },
			}
		end)
		expect(duplicateLocator):toEqual(false)
	end)

	it("refuses a retry policy that names a correctness outcome", function()
		local ok, thrown: unknown = pcall(function()
			return validate {
				id = "p",
				policy = { retry = { maxAttempts = 3, on = { "failed" } } },
				units = { unit "a" },
			}
		end)
		expect(ok):toEqual(false)
		expect((tostring(thrown))):toContain "not an infrastructure outcome"
	end)

	it("refuses more than one attempt with nothing eligible", function()
		local ok = pcall(function()
			return validate {
				id = "p",
				policy = { retry = { maxAttempts = 2, on = {} } },
				units = { unit "a" },
			}
		end)
		expect(ok):toEqual(false)
	end)

	it("selects by id, tag, group and capability without reordering", function()
		expect((idsOf(Plan.select(BASE, { tags = { "neutral" } }).units))):toEqual {
			"alpha/one",
			"alpha/two",
			"gamma/one",
			"delta/one",
		}
		expect((idsOf(Plan.select(BASE, { groups = { "alpha" } }).units))):toEqual { "alpha/one", "alpha/two" }
		expect((idsOf(Plan.select(BASE, { capabilities = { "local-luau" } }).units))):toEqual { "beta/one" }
		expect((idsOf(Plan.select(BASE, { ids = { "gamma/one", "alpha/one" } }).units))):toEqual {
			"alpha/one",
			"gamma/one",
		}
		expect(#Plan.select(BASE, nil).units):toEqual(5)
	end)

	it("narrows by predicate over the same selection subject a harness sees", function()
		local seen: { Verify.SelectionSubject } = {}
		local selected = Plan.select(BASE, {
			predicate = function(subject: Verify.SelectionSubject): boolean
				table.insert(seen, subject)
				return string.find(assert(subject.source), "alpha", 1, true) ~= nil
			end,
		})
		expect((idsOf(selected.units))):toEqual { "alpha/one", "alpha/two" }
		expect(#seen):toEqual(5)
		expect(seen[1].id):toEqual "alpha/one"
		expect(seen[1].source):toEqual "alpha/one.verify.luau"
		expect(seen[1].name):toEqual "alpha/one"
		expect(seen[1].path):toEqual {}
		expect(seen[1].tags):toEqual { "neutral" }
		expect(seen[1].requires):toEqual {}
		expect((idsOf(Plan.select(BASE, {
			groups = { "alpha" },
			predicate = function(subject: Verify.SelectionSubject): boolean
				return subject.id ~= "alpha/two"
			end,
		}).units))):toEqual { "alpha/one" }
	end)

	it("returns exactly the batch count asked for, empty batches included", function()
		local batches = partition({ id = "p", units = { unit "only" } }, 4)
		expect(#batches):toEqual(4)
		expect(#batches[1].units):toEqual(1)
		expect(#batches[4].units):toEqual(0)
		expect(batches[4].id):toEqual "batch-4"
	end)

	it("composes stable case ids in both styles", function()
		expect((Plan.caseId("alpha/one", { "inventory", "release" }, "frees"))):toEqual "alpha/one::inventory > release > frees"
		expect((Plan.caseId("alpha/one", { "inventory" }, "frees", "bare"))):toEqual "inventory > frees"
		expect((pcall(Plan.caseId, "alpha/one", {}, "frees", "invented"))):toEqual(false)
	end)

	it("digests a plan by its meaning and notices every change to it", function()
		local base = Plan.digest(BASE)
		expect(base):toEqual(Plan.digest(Plan.validate(BASE)))
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

describe("cost-aware batching", function()
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

	it("defaults every unit to weight one", function()
		local plan = validate { id = "p", units = { { id = "a", locator = "a.luau" } } }
		expect(plan.units[1].weight):toEqual(1)
	end)

	it("refuses a weight that is not a positive number", function()
		for _, weight in { 0, -3, math.huge, -math.huge } do
			expect(function()
				validate { id = "p", units = { { id = "a", locator = "a.luau", weight = weight } } }
			end):toThrow "weight"
		end
		expect(
			Chunk.load('return validate { id = "p", units = { { id = "a", locator = "a.luau", weight = "heavy" } } }', {
				environment = { validate = validate },
			})
		):toThrow "weight"
	end)

	it("balances declared weight instead of unit count", function()
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
		expect(countedWeights[4]):toEqual(20)
		expect(weightedWeights[4] <= 10):toEqual(true)
		expect(countedWeights[4] > weightedWeights[4]):toEqual(true)
		local seen = 0
		for _, batch in weighted do
			seen += #batch.units
		end
		expect(seen):toEqual(8)
	end)

	it("is identical to count batching when no weight was declared", function()
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
				expect((idsOf(weighted[index].units))):toEqual(idsOf(counted[index].units))
			end
		end
	end)

	it("partitions every unit once, keeps groups whole and repeats deterministically in both modes", function()
		local grouped: Verify.PlanDraft = {
			id = "grouped",
			units = {
				{ id = "a", locator = "a.luau", group = "shared", weight = 9 },
				{ id = "b", locator = "b.luau", group = "shared", weight = 9 },
				{ id = "c", locator = "c.luau", weight = 1 },
			},
		}
		for _, mode in { "count", "weighted" } do
			for _, draft in { BASE, WEIGHTED, grouped } do
				local first = Plan.partition(draft, 3, mode)
				expect(batchIds(Plan.partition(draft, 3, mode))):toEqual(batchIds(first))
				local seen: { [string]: number } = {}
				local groups: { [string]: number } = {}
				for index, batch in first do
					for _, entry in batch.units do
						seen[entry.id] = (seen[entry.id] or 0) + 1
						if entry.group ~= nil then
							groups[entry.group] = groups[entry.group] or index
							expect(index):toEqual(groups[entry.group])
						end
					end
				end
				for _, entry in draft.units do
					expect(seen[entry.id]):toEqual(1)
				end
			end
		end
	end)

	it("changes the plan digest when a weight changes", function()
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
		expect((Plan.digest(WEIGHTED) ~= Plan.digest(heavier))):toEqual(true)
	end)

	it("refuses a batching mode it does not implement", function()
		expect((pcall(function()
			Chunk.load(
				'return partition(plan, 2, "measured")',
				{ environment = { partition = Plan.partition, plan = WEIGHTED } }
			)()
		end))):toEqual(false)
	end)

	it("carries declared weight across the worker wire", function()
		local batches = Plan.partition(WEIGHTED, 1, "weighted")
		local decoded = Batch.decode(Batch.encode(batches[1]))
		expect(decoded.units[1].weight):toEqual(10)
		expect(decoded.units[2].weight):toEqual(1)
	end)
end)

describe("capability negotiation", function()
	it("names what is missing and what the host declared", function()
		local negotiation = Capability.negotiate({ "local-luau", "worker" }, { "worker", "engine-datamodel" })
		expect(negotiation.satisfied):toEqual(false)
		expect(negotiation.missing):toEqual { "engine-datamodel" }
		expect(negotiation.declared):toEqual { "local-luau", "worker" }
		expect((Capability.explain(negotiation))):toContain "missing engine-datamodel"
		expect((Capability.explain(negotiation))):toContain "the host declared local-luau, worker"
	end)

	it("is satisfied by an empty requirement set and never by an empty declaration", function()
		expect(Capability.negotiate({}, {}).satisfied):toEqual(true)
		expect(Capability.negotiate({}, { "anything" }).satisfied):toEqual(false)
		expect((Capability.explain(Capability.negotiate({}, { "anything" })))):toContain "declared none"
	end)

	it("does not depend on the order a host listed its capabilities", function()
		local left = Capability.negotiate({ "b", "a" }, { "a" })
		local right = Capability.negotiate({ "a", "b" }, { "a" })
		expect(left.declared):toEqual(right.declared)
		expect(left.satisfied):toEqual(right.satisfied)
	end)
end)

return nil
