--!strict

local fs = require "@std/fs"
local test = require "@std/test"

local Files = require "../src/lute/files"
local Lute = require "../src/lute"
local Verify = require "../src/core"
local Worker = require "../src/lute/worker"

local function unit(id: string, locator: string): Verify.PlanUnit
	return { id = id, locator = locator, group = nil, tags = {}, requires = {}, deadlineSeconds = nil, weight = 1 }
end

local function batchOf(id: string, units: { Verify.PlanUnit }): Verify.PlanBatch
	return { id = id, index = 1, units = units }
end

local function statusesById(report: Verify.Report): { [string]: string }
	local result: { [string]: string } = {}
	for _, item in report.results do
		result[item.id] = item.status
	end
	return result
end

test.suite("self-registering worker batch", function(suite)
	suite:case("keeps returned-function registration defects outside load classification", function(assert)
		for _, returned in { false, true } do
			local classified = 0
			local report = Worker.runBatch(batchOf("b", { unit("u", "spec://bad") }), {
				load = function(): unknown
					if returned then
						return function()
							error("registration defect", 0)
						end
					end
					return 7
				end,
				classifyLoadFailure = function()
					classified += 1
					return { status = "skipped", reason = "must not hide defects" }
				end,
			})
			assert.eq(classified, 0)
			assert.eq(report.failed, 1)
			assert.eq(report.skipped, 0)
			assert.eq(report.results[1].id, if returned then "unit:u:registration" else "unit:u:load")
		end
	end)

	suite:case("registers a unit as a side effect of loading it", function(assert)
		local batch = batchOf("b", { unit("u1", "spec://one") })
		local report = Worker.runBatchSelfRegistering(batch, {
			load = function(_locator: string, harness: Verify.Harness)
				harness:suite("self-registered", function()
					harness:case("passes", function(context)
						context:expect(1 + 1):toBe(2)
					end)
				end)
			end,
		})
		assert.eq(report.passed, 1)
		assert.eq(report.failed, 0)
	end)

	suite:case("gives each unit its own harness even though loading is what registers it", function(assert)
		local batch = batchOf("b", { unit("u1", "spec://one"), unit("u2", "spec://two") })
		local seen: { [string]: number } = {}
		local report = Worker.runBatchSelfRegistering(batch, {
			load = function(locator: string, harness: Verify.Harness)
				seen[locator] = (seen[locator] or 0) + 1
				harness:suite("s", function()
					harness:case("one case", function(context)
						context:expect(true):toBe(true)
					end)
				end)
			end,
		})
		assert.eq(report.passed, 2)
		assert.eq(seen["spec://one"], 1)
		assert.eq(seen["spec://two"], 1)
	end)

	suite:case("names a locator that raises while registering as a failed registration", function(assert)
		local batch = batchOf("b", { unit("u1", "spec://good"), unit("u2", "spec://bad") })
		local report = Worker.runBatchSelfRegistering(batch, {
			load = function(locator: string, harness: Verify.Harness)
				if locator == "spec://bad" then
					error("boom", 0)
				end
				harness:suite("s", function()
					harness:case("passes", function(context)
						context:expect(true):toBe(true)
					end)
				end)
			end,
		})
		assert.eq(report.passed, 1)
		assert.eq(report.failed, 1)
		local statuses = statusesById(report)
		assert.eq(statuses["unit:u2:registration"], "failed")
	end)

	suite:case("classifies a raise into a skip or an unsupported case when told to", function(assert)
		local batch = batchOf("b", { unit("u1", "spec://skip"), unit("u2", "spec://missing-capability") })
		local report = Worker.runBatchSelfRegistering(batch, {
			load = function(locator: string, _harness: Verify.Harness)
				error(locator, 0)
			end,
			classifyLoadFailure = function(locator: string, _thrown: unknown)
				if locator == "spec://skip" then
					return { status = "skipped", reason = "not applicable here" }
				end
				return { status = "unsupported", missingCapabilities = { "engine" } }
			end,
		})
		local statuses = statusesById(report)
		assert.eq(statuses["unit:u1:registration"], "skipped")
		assert.eq(statuses["unit:u2:registration"], "unsupported")
		assert.eq(report.passed, 0)
		assert.eq(report.failed, 0)
	end)

	suite:case("agrees with the returned-function worker on an equivalent batch", function(assert)
		local batch = batchOf("b", { unit("u1", "spec://one"), unit("u2", "spec://two") })
		local returnedReport = Worker.runBatch(batch, {
			load = function(_locator: string): unknown
				return function(harness: Verify.Harness)
					harness:suite("s", function()
						harness:case("passes", function(context)
							context:expect(true):toBe(true)
						end)
					end)
				end
			end,
		})
		local selfRegisteringReport = Worker.runBatchSelfRegistering(batch, {
			load = function(_locator: string, harness: Verify.Harness)
				harness:suite("s", function()
					harness:case("passes", function(context)
						context:expect(true):toBe(true)
					end)
				end)
			end,
		})
		assert.eq(Verify.verdictDigest(selfRegisteringReport), Verify.verdictDigest(returnedReport))
		assert.eq(selfRegisteringReport.passed, returnedReport.passed)
	end)
end)

local ROOT = ".lute/tmp/verify-worker-spec"
local UNITS = ROOT .. "/units"
local ensureDirectory = Files.ensureDirectory

local function selfRegisteringFixture(name: string, body: string): string
	ensureDirectory(ROOT)
	ensureDirectory(UNITS)
	local locator = ("%s/%s.luau"):format(UNITS, name)
	fs.writeStringToFile(
		locator,
		table.concat({
			"--!strict",
			'local Ambient = require "../../../../examples/self-registering-ambient"',
			"local harness = Ambient.get()",
			body,

			"return nil",
			"",
		}, "\n")
	)
	return locator
end

local PASSING = selfRegisteringFixture(
	"passing",
	table.concat({
		'harness:suite("self-registered", function()',
		'\tharness:case("passes", function(context)',
		"\t\tcontext:expect(2 + 2):toBe(4)",
		"\tend)",
		"end)",
	}, "\n")
)

local SECOND = selfRegisteringFixture(
	"second",
	table.concat({
		'harness:suite("self-registered", function()',
		'\tharness:case("also passes", function(context)',
		"\t\tcontext:expect(true):toBe(true)",
		"\tend)",
		"end)",
	}, "\n")
)

local function planOf(id: string, locators: { string }): Verify.PlanDraft
	local units: { Verify.PlanUnitDraft } = {}
	for index, locator in locators do
		table.insert(units, { id = ("u%d"):format(index), locator = locator })
	end
	return { id = id, units = units }
end

test.suite("self-registering worker processes", function(suite)
	suite:case("runs a real self-registering one-shot worker end to end", function(assert)
		local plan = planOf("one-shot", { PASSING, SECOND })
		local execution = Verify.execute(
			plan,
			Lute.host { worker = "examples/self-registering-worker.luau", directory = ROOT .. "/fresh" }
		)
		assert.eq(execution.report.passed, 2)
		assert.eq(execution.report.failed, 0)
	end)

	suite:case("runs a real self-registering pooled worker end to end", function(assert)
		local plan = planOf("pooled", { PASSING, SECOND })
		local pool = Lute.pool { worker = "examples/self-registering-pool-worker.luau", directory = ROOT .. "/pool" }
		local execution = Verify.execute(plan, pool, { batchCount = 2, parallel = 2 })
		pool:close()
		assert.eq(execution.report.passed, 2)
		assert.eq(execution.report.failed, 0)
	end)

	suite:case("agrees with the fresh-process host and the pooled host on the same plan", function(assert)
		local plan = planOf("parity", { PASSING, SECOND })
		local fresh = Verify.execute(
			plan,
			Lute.host { worker = "examples/self-registering-worker.luau", directory = ROOT .. "/parity-fresh" }
		)
		local pool =
			Lute.pool { worker = "examples/self-registering-pool-worker.luau", directory = ROOT .. "/parity-pool" }
		local pooled = Verify.execute(plan, pool, { batchCount = 2, parallel = 2 })
		pool:close()
		assert.eq(Verify.verdictDigest(pooled.report), Verify.verdictDigest(fresh.report))
	end)
end)
