--!strict

local test = require "@std/test"

local Lute = require "../src/lute"
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

test.suite("execution plan", function(suite)
	suite:case("normalizes a draft into a versioned plan", function(assert)
		local plan = Verify.validatePlan(BASE)
		assert.eq(plan.schemaVersion, Verify.PLAN_SCHEMA_VERSION)
		assert.eq(plan.policy.maxParallelBatches, 1)
		assert.eq(plan.policy.failFast, false)
		assert.eq(plan.policy.caseIdStyle, "unit-prefixed")
		assert.eq(plan.policy.retry.maxAttempts, 1)
		assert.eq(plan.units[3].requires, { "local-luau" })
		assert.eq(plan.units[1].tags, { "neutral" })
	end)

	suite:case("refuses a duplicate unit id and a duplicate locator", function(assert)
		local duplicateId = pcall(Verify.validatePlan, {
			id = "p",
			units = { unit "a", { id = "a", locator = "b.verify.luau" } },
		})
		assert.eq(duplicateId, false)
		local duplicateLocator = pcall(Verify.validatePlan, {
			id = "p",
			units = { unit "a", { id = "b", locator = "a.verify.luau" } },
		})
		assert.eq(duplicateLocator, false)
	end)

	suite:case("refuses a retry policy that names a correctness outcome", function(assert)
		local ok, thrown: any = pcall(Verify.validatePlan, {
			id = "p",
			policy = { retry = { maxAttempts = 3, on = { "failed" } } },
			units = { unit "a" },
		})
		assert.eq(ok, false)
		assert.strContains(tostring(thrown), "not an infrastructure outcome")
	end)

	suite:case("refuses more than one attempt with nothing eligible", function(assert)
		local ok = pcall(Verify.validatePlan, {
			id = "p",
			policy = { retry = { maxAttempts = 2, on = {} } },
			units = { unit "a" },
		})
		assert.eq(ok, false)
	end)

	suite:case("selects by id, tag, group and capability without reordering", function(assert)
		assert.eq(idsOf(Verify.selectPlan(BASE, { tags = { "neutral" } }).units), {
			"alpha/one",
			"alpha/two",
			"gamma/one",
			"delta/one",
		})
		assert.eq(idsOf(Verify.selectPlan(BASE, { groups = { "alpha" } }).units), { "alpha/one", "alpha/two" })
		assert.eq(idsOf(Verify.selectPlan(BASE, { capabilities = { "local-luau" } }).units), { "beta/one" })
		assert.eq(idsOf(Verify.selectPlan(BASE, { ids = { "gamma/one", "alpha/one" } }).units), {
			"alpha/one",
			"gamma/one",
		})
		assert.eq(#Verify.selectPlan(BASE, nil).units, 5)
	end)

	suite:case("narrows by predicate over the same selection subject a harness sees", function(assert)
		local seen: { Verify.SelectionSubject } = {}
		local selected = Verify.selectPlan(BASE, {
			predicate = function(subject: Verify.SelectionSubject): boolean
				table.insert(seen, subject)
				return string.find(subject.source :: string, "alpha", 1, true) ~= nil
			end,
		})
		assert.eq(idsOf(selected.units), { "alpha/one", "alpha/two" })
		assert.eq(#seen, 5)
		assert.eq(seen[1].id, "alpha/one")
		assert.eq(seen[1].source, "alpha/one.verify.luau")
		assert.eq(seen[1].name, "alpha/one")
		assert.eq(seen[1].path, {})
		assert.eq(seen[1].tags, { "neutral" })
		assert.eq(seen[1].requires, {})
		assert.eq(
			idsOf(Verify.selectPlan(BASE, {
				groups = { "alpha" },
				predicate = function(subject: Verify.SelectionSubject): boolean
					return subject.id ~= "alpha/two"
				end,
			}).units),
			{ "alpha/one" }
		)
	end)

	suite:case("keeps a group whole and partitions the same way every time", function(assert)
		local first = batchIds(Verify.partitionPlan(BASE, 3))
		local second = batchIds(Verify.partitionPlan(BASE, 3))
		assert.eq(first, second)
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
					assert.eq(index, alphaBatch)
				end
			end
		end
	end)

	suite:case("returns exactly the batch count asked for, empty batches included", function(assert)
		local batches = Verify.partitionPlan({ id = "p", units = { unit "only" } }, 4)
		assert.eq(#batches, 4)
		assert.eq(#batches[1].units, 1)
		assert.eq(#batches[4].units, 0)
		assert.eq(batches[4].id, "batch-4")
	end)

	suite:case("covers every unit exactly once across batches", function(assert)
		local seen: { [string]: number } = {}
		for _, batch in Verify.partitionPlan(BASE, 3) do
			for _, id in idsOf(batch.units) do
				seen[id] = (seen[id] or 0) + 1
			end
		end
		for _, entry in Verify.validatePlan(BASE).units do
			assert.eq(seen[entry.id], 1)
		end
	end)

	suite:case("composes stable case ids in both styles", function(assert)
		assert.eq(
			Verify.caseId("alpha/one", { "inventory", "release" }, "frees"),
			"alpha/one::inventory > release > frees"
		)
		assert.eq(Verify.caseId("alpha/one", { "inventory" }, "frees", "bare"), "inventory > frees")
		assert.eq(pcall(Verify.caseId, "alpha/one", {}, "frees", "invented"), false)
	end)

	suite:case("digests a plan by its meaning and notices every change to it", function(assert)
		local base = Verify.planDigest(BASE)
		assert.eq(base, Verify.planDigest(Verify.validatePlan(BASE)))
		local reordered = table.clone(BASE)
		reordered.units = { BASE.units[2], BASE.units[1], BASE.units[3], BASE.units[4], BASE.units[5] }
		assert.that(Verify.planDigest(reordered) ~= base)
		local retagged: Verify.PlanDraft = {
			id = "example",
			policy = { failFast = true },
			units = BASE.units,
		}
		assert.that(Verify.planDigest(retagged) ~= base)
	end)

	suite:case("bridges a schema-v1 manifest into a plan without losing a field", function(assert)
		local plan = Verify.planFromManifest {
			schemaVersion = 1,
			entries = {
				{ id = "a", source = "a.verify.luau", group = "g", tags = { "neutral" }, requires = {} },
				{ id = "b", source = "b.lute.verify.luau", group = "g", tags = { "lute" }, requires = { "lute" } },
			},
		}
		assert.eq(idsOf(plan.units), { "a", "b" })
		assert.eq(plan.units[2].locator, "b.lute.verify.luau")
		assert.eq(plan.units[2].requires, { "lute" })
		assert.eq(plan.units[1].group, "g")
	end)
end)

test.suite("cost-aware batching", function(suite)
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

	suite:case("defaults every unit to weight one", function(assert)
		local plan = Verify.validatePlan { id = "p", units = { { id = "a", locator = "a.luau" } } }
		assert.eq(plan.units[1].weight, 1)
	end)

	suite:case("refuses a weight that is not a positive number", function(assert)
		local function withWeight(weight: any): () -> ()
			return function()
				Verify.validatePlan { id = "p", units = { { id = "a", locator = "a.luau", weight = weight } } }
			end
		end
		assert.eq(pcall(withWeight(0)), false)
		assert.eq(pcall(withWeight(-3)), false)
		assert.eq(pcall(withWeight "heavy"), false)
		assert.eq(pcall(withWeight(math.huge)), false)
		assert.eq(pcall(withWeight(-math.huge)), false)
	end)

	suite:case("balances declared weight instead of unit count", function(assert)
		local counted = Verify.partitionPlan(WEIGHTED, 4, "count")
		local weighted = Verify.partitionPlan(WEIGHTED, 4, "weighted")
		local countedWeights: { number } = {}
		local weightedWeights: { number } = {}
		for index = 1, 4 do
			table.insert(countedWeights, weightOf(counted[index]))
			table.insert(weightedWeights, weightOf(weighted[index]))
		end
		table.sort(countedWeights)
		table.sort(weightedWeights)
		assert.eq(countedWeights[4], 20)
		assert.eq(weightedWeights[4] <= 10, true)
		assert.eq(countedWeights[4] > weightedWeights[4], true)
		local seen = 0
		for _, batch in weighted do
			seen += #batch.units
		end
		assert.eq(seen, 8)
	end)

	suite:case("is identical to count batching when no weight was declared", function(assert)
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
			local counted = Verify.partitionPlan(plan, count, "count")
			local weighted = Verify.partitionPlan(plan, count, "weighted")
			for index = 1, count do
				assert.eq(idsOf(weighted[index].units), idsOf(counted[index].units))
			end
		end
	end)

	suite:case("keeps a group whole whichever mode partitioned it", function(assert)
		local plan: Verify.PlanDraft = {
			id = "grouped",
			units = {
				{ id = "a", locator = "a.luau", group = "shared", weight = 9 },
				{ id = "b", locator = "b.luau", group = "shared", weight = 9 },
				{ id = "c", locator = "c.luau", weight = 1 },
			},
		}
		local weighted = Verify.partitionPlan(plan, 3, "weighted")
		for _, batch in weighted do
			local ids = idsOf(batch.units)
			if table.find(ids, "a") ~= nil then
				assert.eq(table.find(ids, "b") ~= nil, true)
			end
		end
	end)

	suite:case("is a pure function of the plan and never of a timing", function(assert)
		local first = Verify.partitionPlan(WEIGHTED, 3, "weighted")
		for _ = 1, 10 do
			local again = Verify.partitionPlan(WEIGHTED, 3, "weighted")
			for index = 1, 3 do
				assert.eq(idsOf(again[index].units), idsOf(first[index].units))
			end
		end
	end)

	suite:case("changes the plan digest when a weight changes", function(assert)
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
		assert.eq(Verify.planDigest(WEIGHTED) ~= Verify.planDigest(heavier), true)
	end)

	suite:case("refuses a batching mode it does not implement", function(assert)
		assert.eq(
			pcall(function()
				(Verify.partitionPlan :: any)(WEIGHTED, 2, "measured")
			end),
			false
		)
	end)

	suite:case("carries declared weight across the worker wire", function(assert)
		local batches = Verify.partitionPlan(WEIGHTED, 1, "weighted")
		local decoded = Lute.decodeBatch(Lute.encodeBatch(batches[1]))
		assert.eq(decoded.units[1].weight, 10)
		assert.eq(decoded.units[2].weight, 1)
	end)
end)

test.suite("capability negotiation", function(suite)
	suite:case("names what is missing and what the host declared", function(assert)
		local negotiation = Verify.negotiate({ "local-luau", "worker" }, { "worker", "engine-datamodel" })
		assert.eq(negotiation.satisfied, false)
		assert.eq(negotiation.missing, { "engine-datamodel" })
		assert.eq(negotiation.declared, { "local-luau", "worker" })
		assert.strContains(Verify.explainCapabilities(negotiation), "missing engine-datamodel")
		assert.strContains(Verify.explainCapabilities(negotiation), "the host declared local-luau, worker")
	end)

	suite:case("is satisfied by an empty requirement set and never by an empty declaration", function(assert)
		assert.eq(Verify.negotiate({}, {}).satisfied, true)
		assert.eq(Verify.negotiate({}, { "anything" }).satisfied, false)
		assert.strContains(Verify.explainCapabilities(Verify.negotiate({}, { "anything" })), "declared none")
	end)

	suite:case("does not depend on the order a host listed its capabilities", function(assert)
		local left = Verify.negotiate({ "b", "a" }, { "a" })
		local right = Verify.negotiate({ "a", "b" }, { "a" })
		assert.eq(left.declared, right.declared)
		assert.eq(left.satisfied, right.satisfied)
	end)
end)

test.suite("manifest admission", function(suite)
	suite:case("preserves explicit source order and refuses ambiguous identities", function(assert)
		local entries: { Verify.ManifestEntry } = {
			{ id = "second", source = "b.verify.luau", tags = { "x", "x" } },
			{ id = "first", source = "a.verify.luau" },
		}
		local manifest = Verify.validateManifest { schemaVersion = 1, entries = entries }
		assert.eq(manifest.entries[1].id, "second")
		assert.eq(manifest.entries[1].tags, { "x" })
		assert.eq(Verify.planFromManifest(manifest).units[2].locator, "a.verify.luau")
		for _, broken in
			{
				{ schemaVersion = 2, entries = entries },
				{ schemaVersion = 1, entries = { entries[1], entries[1] } },
				{ schemaVersion = 1, entries = { { id = "other", source = "b.verify.luau" }, entries[1] } },
				{ schemaVersion = 1, entries = { { id = "", source = "b.verify.luau" } } },
				{ schemaVersion = 1, entries = { { id = "x", source = "b.luau" } } },
			}
		do
			assert.eq(pcall(Verify.validateManifest, broken), false)
		end
	end)
end)
