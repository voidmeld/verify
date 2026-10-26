--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local ReportModel = require "../src/core/report"
local fs = require "@std/fs"

local Files = require "../src/lute/files"
local Lute = require "../src/lute"
local Verify = require "../src/core"
local Worker = require "../src/lute/worker"
local Parsing = require "../src/lute/worker"
local task = require "@std/task"

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

it("queued workers refill a free slot while another batch is still running", function()
	local host = Lute.host { worker = "unused-worker.luau" }
	local active, maximum = 0, 0
	local thirdStarted, overlapped = false, false
	host.runBatch = function(batch)
		active += 1
		maximum = math.max(maximum, active)
		if batch.index == 1 then
			local deadline = os.clock() + 2
			while not thirdStarted and os.clock() < deadline do
				task.wait(0.001)
			end
		elseif batch.index == 3 then
			thirdStarted = true
			overlapped = active == 2
		end
		local harness = Verify.createHarness { now = os.clock, source = batch.units[1].locator }
		harness:case("passes", function(context)
			context:expect(true):toBe(true)
		end)
		active -= 1
		return {
			status = "returned",
			report = harness:run { executor = "queue-fixture", environment = { runtime = "lute" } },
		}
	end
	local plan: Verify.PlanDraft = { id = "rolling", units = {} }
	for index = 1, 6 do
		table.insert(plan.units, { id = tostring(index), locator = "queued-" .. tostring(index) })
	end
	local result = Verify.execute(plan, host, { batchCount = 6, parallel = 2 })
	expect(overlapped):toBe(true)
	expect(maximum):toBe(2)
	expect(active):toBe(0)
	expect(result.report.passed):toBe(6)
	expect(result.report.failed):toBe(0)
end)
describe("self-registering worker batch", function()
	it("keeps returned-function registration defects outside load classification", function()
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
			expect(classified):toEqual(0)
			expect(report.failed):toEqual(1)
			expect(report.skipped):toEqual(0)
			expect(report.results[1].id):toEqual(if returned then "unit:u:registration" else "unit:u:load")
		end
	end)

	it("registers a unit as a side effect of loading it", function()
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
		expect(report.passed):toEqual(1)
		expect(report.failed):toEqual(0)
	end)

	it("gives each unit its own harness even though loading is what registers it", function()
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
		expect(report.passed):toEqual(2)
		expect(seen["spec://one"]):toEqual(1)
		expect(seen["spec://two"]):toEqual(1)
	end)

	it("names a locator that raises while registering as a failed registration", function()
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
		expect(report.passed):toEqual(1)
		expect(report.failed):toEqual(1)
		local statuses = statusesById(report)
		expect(statuses["unit:u2:registration"]):toEqual "failed"
	end)

	it("classifies a raise into a skip or an unsupported case when told to", function()
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
		expect(statuses["unit:u1:registration"]):toEqual "skipped"
		expect(statuses["unit:u2:registration"]):toEqual "unsupported"
		expect(report.passed):toEqual(0)
		expect(report.failed):toEqual(0)
	end)

	it("agrees with the returned-function worker on an equivalent batch", function()
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
		expect((ReportModel.verdictDigest(selfRegisteringReport))):toEqual(ReportModel.verdictDigest(returnedReport))
		expect(selfRegisteringReport.passed):toEqual(returnedReport.passed)
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

describe("self-registering worker processes", function()
	it("runs a real self-registering one-shot worker end to end", function()
		local plan = planOf("one-shot", { PASSING, SECOND })
		local execution = Verify.execute(
			plan,
			Lute.host { worker = "examples/self-registering-worker.luau", directory = ROOT .. "/fresh" }
		)
		expect(execution.report.passed):toEqual(2)
		expect(execution.report.failed):toEqual(0)
	end)
end)

describe("worker arguments", function()
	local function run(arguments: { string }): Verify.Report
		local parsed = Parsing.parseArguments(arguments)
		local session = Verify.createSession {
			executor = "args",
			environment = {},
			now = os.clock,
			selection = parsed.selection,
		}
		session:open "source"
		local harness = session:harness()
		harness:case("quick", { id = "quick", tags = { "tier:fast" }, run = function() end })
		harness:case("long", { id = "long", tags = { "tier:slow" }, run = function() end })
		harness:case("always", { id = "always", run = function() end })
		session:close()
		return session:run()
	end

	it("collects the arguments after the separator", function()
		local plain = Parsing.parseArguments { "batch.json", "result.json", "--", "--tier=fast", "--mine" }
		expect(plain.extras):toEqual { "--tier=fast", "--mine" }
		local bare = Parsing.parseArguments { "batch.json", "result.json" }
		expect(bare.extras):toEqual {}
		expect(bare.selection):toEqual(nil)
	end)

	it("selects a tier, keeping untiered cases, and accounts the rest as deselected", function()
		local report = run { "b", "r", "--", "--tier=fast" }
		expect(statusesById(report)):toEqual { quick = "passed", long = "skipped", always = "passed" }
		expect(report.skipped):toEqual(1)
		local both = run { "b", "r", "--", "--tier=fast,slow" }
		expect(both.passed):toEqual(3)
	end)

	it("selects by case-name substring and source and accounts the rest as deselected", function()
		local byName = run { "b", "r", "--", "--name=ong" }
		expect(statusesById(byName)):toEqual { quick = "skipped", long = "passed", always = "skipped" }
		local both = run { "b", "r", "--", "--name=ong", "--source=source" }
		expect(both.passed):toEqual(1)
		local other = run { "b", "r", "--", "--source=elsewhere" }
		expect(other.passed):toEqual(0)
		expect(other.skipped):toEqual(3)
		local none = run { "b", "r", "--", "--name=absent" }
		expect(none.passed):toEqual(0)
	end)

	it("selects named cases and tags and ignores arguments it does not own", function()
		local named = run { "b", "r", "--", "--case=long", "--unrelated" }
		expect(statusesById(named)):toEqual { quick = "skipped", long = "passed", always = "skipped" }
		expect(named.skipped):toEqual(2)
		local tagged = run { "b", "r", "--", "--tag=tier:slow" }
		expect(statusesById(tagged)):toEqual { quick = "skipped", long = "passed", always = "skipped" }
		local ignored = run { "b", "r", "--", "--unrelated" }
		expect(ignored.passed):toEqual(3)
	end)
end)

return nil
