--!strict

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

return function(suite: Verify.Harness)
	suite:case("queued workers refill a free slot while another batch is still running", function(check)
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
		check:expect(overlapped):toBe(true)
		check:expect(maximum):toBe(2)
		check:expect(active):toBe(0)
		check:expect(result.report.passed):toBe(6)
		check:expect(result.report.failed):toBe(0)
	end)
	suite:suite("self-registering worker batch", function()
		suite:case("keeps returned-function registration defects outside load classification", function(check)
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
				check:expect(classified):toEqual(0)
				check:expect(report.failed):toEqual(1)
				check:expect(report.skipped):toEqual(0)
				check:expect(report.results[1].id):toEqual(if returned then "unit:u:registration" else "unit:u:load")
			end
		end)

		suite:case("registers a unit as a side effect of loading it", function(check)
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
			check:expect(report.passed):toEqual(1)
			check:expect(report.failed):toEqual(0)
		end)

		suite:case("gives each unit its own harness even though loading is what registers it", function(check)
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
			check:expect(report.passed):toEqual(2)
			check:expect(seen["spec://one"]):toEqual(1)
			check:expect(seen["spec://two"]):toEqual(1)
		end)

		suite:case("names a locator that raises while registering as a failed registration", function(check)
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
			check:expect(report.passed):toEqual(1)
			check:expect(report.failed):toEqual(1)
			local statuses = statusesById(report)
			check:expect(statuses["unit:u2:registration"]):toEqual "failed"
		end)

		suite:case("classifies a raise into a skip or an unsupported case when told to", function(check)
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
			check:expect(statuses["unit:u1:registration"]):toEqual "skipped"
			check:expect(statuses["unit:u2:registration"]):toEqual "unsupported"
			check:expect(report.passed):toEqual(0)
			check:expect(report.failed):toEqual(0)
		end)

		suite:case("agrees with the returned-function worker on an equivalent batch", function(check)
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
			check
				:expect((ReportModel.verdictDigest(selfRegisteringReport)))
				:toEqual(ReportModel.verdictDigest(returnedReport))
			check:expect(selfRegisteringReport.passed):toEqual(returnedReport.passed)
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

	suite:suite("self-registering worker processes", function()
		suite:case("runs a real self-registering one-shot worker end to end", function(check)
			local plan = planOf("one-shot", { PASSING, SECOND })
			local execution = Verify.execute(
				plan,
				Lute.host { worker = "examples/self-registering-worker.luau", directory = ROOT .. "/fresh" }
			)
			check:expect(execution.report.passed):toEqual(2)
			check:expect(execution.report.failed):toEqual(0)
		end)
	end)

	suite:suite("worker arguments", function()
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

		suite:case("collects the arguments after the separator", function(check)
			local plain = Parsing.parseArguments { "batch.json", "result.json", "--", "--tier=fast", "--mine" }
			check:expect(plain.extras):toEqual { "--tier=fast", "--mine" }
			local bare = Parsing.parseArguments { "batch.json", "result.json" }
			check:expect(bare.extras):toEqual {}
			check:expect(bare.selection):toEqual(nil)
		end)

		suite:case("selects a tier, keeping untiered cases, and accounts the rest as deselected", function(check)
			local report = run { "b", "r", "--", "--tier=fast" }
			check:expect(statusesById(report)):toEqual { quick = "passed", long = "skipped", always = "passed" }
			check:expect(report.skipped):toEqual(1)
			local both = run { "b", "r", "--", "--tier=fast,slow" }
			check:expect(both.passed):toEqual(3)
		end)

		suite:case("selects by case-name substring and source and accounts the rest as deselected", function(check)
			local byName = run { "b", "r", "--", "--name=ong" }
			check:expect(statusesById(byName)):toEqual { quick = "skipped", long = "passed", always = "skipped" }
			local both = run { "b", "r", "--", "--name=ong", "--source=source" }
			check:expect(both.passed):toEqual(1)
			local other = run { "b", "r", "--", "--source=elsewhere" }
			check:expect(other.passed):toEqual(0)
			check:expect(other.skipped):toEqual(3)
			local none = run { "b", "r", "--", "--name=absent" }
			check:expect(none.passed):toEqual(0)
		end)

		suite:case("selects named cases and tags and ignores arguments it does not own", function(check)
			local named = run { "b", "r", "--", "--case=long", "--unrelated" }
			check:expect(statusesById(named)):toEqual { quick = "skipped", long = "passed", always = "skipped" }
			check:expect(named.skipped):toEqual(2)
			local tagged = run { "b", "r", "--", "--tag=tier:slow" }
			check:expect(statusesById(tagged)):toEqual { quick = "skipped", long = "passed", always = "skipped" }
			local ignored = run { "b", "r", "--", "--unrelated" }
			check:expect(ignored.passed):toEqual(3)
		end)
	end)
end
