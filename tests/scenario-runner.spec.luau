--!strict

local Verify = require "../src/core"

local Roblox = require "../src/roblox"

local COMPLETE = "SUMMARY"
local CANDIDATE = "RESULTS"
local BOUND = "place=1"
local HALT = "kicked:"

local function predicates(overrides: { [string]: any }): Roblox.ScenarioPredicates
	return {
		candidate = overrides.candidate or function(bytes: string): boolean
			return string.find(bytes, CANDIDATE, 1, true) ~= nil
		end,
		complete = overrides.complete or function(bytes: string): boolean
			return string.find(bytes, COMPLETE, 1, true) ~= nil
		end,
		bound = overrides.bound or function(bytes: string): boolean
			return string.find(bytes, BOUND, 1, true) ~= nil
		end,
		observed = overrides.observed or function(bytes: string): boolean
			return string.find(bytes, "ARMED", 1, true) ~= nil
		end,
		halt = overrides.halt or function(bytes: string): string?
			return string.match(bytes, HALT .. "%S+")
		end,
		defect = overrides.defect or function(bytes: string): string?
			return if string.find(bytes, "TRUNCATED", 1, true) ~= nil then "truncated_record" else nil
		end,
		latch = overrides.latch,
	}
end

type Sources = { [string]: string }

local function deps(sources: Sources, overrides: { [string]: any }): Roblox.ScenarioDeps
	local ticks = 0
	local steps: { Sources } = overrides.steps or {}
	local current = sources
	return {
		start = function(): (boolean, string?)
			if overrides.startFails then
				error "driver refused"
			end
			return overrides.started ~= false, nil
		end,
		list = function(): ({ string }?, string?)
			if overrides.listFails then
				return nil, "list refused"
			end
			local names: { string } = {}
			for name in current do
				table.insert(names, name)
			end
			table.sort(names)
			return names, nil
		end,
		read = function(reference: string): string?
			return current[reference]
		end,
		now = function(): number
			if overrides.clockFails then
				return math.huge
			end
			return ticks
		end,
		wait = function(): boolean
			if overrides.waitFails then
				return false
			end
			ticks += 1
			local step = steps[ticks]
			if step ~= nil then
				current = step
			end
			return true
		end,
	}
end

local function options(overrides: { [string]: any }): Roblox.ScenarioOptions
	return {
		deadlineSeconds = overrides.deadlineSeconds or 5,
		exclusive = overrides.exclusive == true,
		reasons = overrides.reasons,
	}
end

local REASONS = Roblox.DEFAULT_SCENARIO_REASONS

return function(suite: Verify.Harness)
	suite:suite("scenario baseline acquisition", function()
		suite:case("refuses an unreadable old source before invoking the driver", function(check)
			local started = false
			local observed = Roblox.observeScenario({
				start = function()
					started = true
					return true, nil
				end,
				list = function()
					return { "old.log" }, nil
				end,
				read = function()
					return nil
				end,
				now = function()
					return 0
				end,
				wait = function()
					return false
				end,
			}, predicates {}, { deadlineSeconds = 1, exclusive = true })
			check:expect(started):toEqual(false)
			check:expect(observed.reason):toEqual(Roblox.DEFAULT_SCENARIO_REASONS.readFailed)
			check:expect(observed.reference):toEqual "old.log"
		end)
	end)

	suite:suite("roblox scenario runner observation", function()
		suite:case("selects a source that appeared after the baseline and completed", function(check)
			local selection = Roblox.observeScenario(
				deps({}, { steps = { { ["/run.log"] = "ARMED RESULTS SUMMARY" } } }),
				predicates {},
				options {}
			)
			check:expect(selection.reason):toEqual(nil)
			check:expect(selection.reference):toEqual "/run.log"
			check:expect(selection.mode):toEqual "new"
			check:expect(selection.bytes):toEqual "ARMED RESULTS SUMMARY"
			check:expect(selection.whole):toEqual "ARMED RESULTS SUMMARY"
		end)

		suite:case("reads only the bytes a reused source gained after the baseline", function(check)
			local selection = Roblox.observeScenario(
				deps(
					{ ["/run.log"] = "stale bytes" },
					{ steps = { { ["/run.log"] = "stale bytes ARMED RESULTS SUMMARY" } } }
				),
				predicates {},
				options {}
			)
			check:expect(selection.reason):toEqual(nil)
			check:expect(selection.mode):toEqual "reused"
			check:expect(selection.offset):toEqual(11)
			check:expect(selection.bytes):toEqual " ARMED RESULTS SUMMARY"
			check:expect(selection.whole):toEqual "stale bytes ARMED RESULTS SUMMARY"
		end)

		suite:case("ignores a source present at baseline that never grew", function(check)
			local selection = Roblox.observeScenario(
				deps(
					{ ["/old.log"] = "ARMED RESULTS SUMMARY" },
					{ steps = { { ["/old.log"] = "ARMED RESULTS SUMMARY", ["/run.log"] = "ARMED RESULTS SUMMARY" } } }
				),
				predicates {},
				options {}
			)
			check:expect(selection.reference):toEqual "/run.log"
			check:expect(selection.mode):toEqual "new"
		end)

		suite:case("latches a marker seen on a poll before the run completed", function(check)
			local selection = Roblox.observeScenario(
				deps({}, {
					steps = {
						{ ["/run.log"] = "ARMED" },
						{ ["/run.log"] = "ARMED RESULTS SUMMARY" },
					},
				}),
				predicates {
					latch = function(bytes: string): boolean
						return string.find(bytes, "ARMED", 1, true) ~= nil
					end,
				},
				options {}
			)
			check:expect(selection.latched):toEqual(true)
			check:expect(selection.reason):toEqual(nil)
		end)

		suite:case("waits while a candidate source has not completed", function(check)
			local selection = Roblox.observeScenario(
				deps({}, {
					steps = {
						{ ["/run.log"] = "ARMED RESULTS" },
						{ ["/run.log"] = "ARMED RESULTS" },
						{ ["/run.log"] = "ARMED RESULTS SUMMARY" },
					},
				}),
				predicates {},
				options {}
			)
			check:expect(selection.reason):toEqual(nil)
			check:expect(selection.bytes):toEqual "ARMED RESULTS SUMMARY"
		end)
	end)

	suite:suite("roblox scenario runner refusals", function()
		suite:case("refuses two sources that both look like this run", function(check)
			local selection = Roblox.observeScenario(
				deps({}, {
					steps = {
						{ ["/a.log"] = "ARMED RESULTS SUMMARY", ["/b.log"] = "ARMED RESULTS SUMMARY" },
					},
				}),
				predicates {},
				options {}
			)
			check:expect(selection.reason):toEqual(REASONS.ambiguous)
			check:expect(selection.reference):toEqual ""
		end)

		suite:case("refuses an appeared and a reused candidate together when the run is exclusive", function(check)
			local selection = Roblox.observeScenario(
				deps({ ["/old.log"] = "x" }, {
					steps = {
						{ ["/old.log"] = "x ARMED RESULTS SUMMARY", ["/new.log"] = "ARMED RESULTS SUMMARY" },
					},
				}),
				predicates {},
				options { exclusive = true }
			)
			check:expect(selection.reason):toEqual(REASONS.ambiguous)
		end)

		suite:case("accepts the appeared candidate over a reused one when the run is not exclusive", function(check)
			local selection = Roblox.observeScenario(
				deps({ ["/old.log"] = "x" }, {
					steps = {
						{ ["/old.log"] = "x ARMED RESULTS SUMMARY", ["/new.log"] = "ARMED RESULTS SUMMARY" },
					},
				}),
				predicates {},
				options {}
			)
			check:expect(selection.reason):toEqual(nil)
			check:expect(selection.reference):toEqual "/new.log"
		end)

		suite:case("stops on a halting line without selecting a source", function(check)
			local selection = Roblox.observeScenario(
				deps({}, { steps = { { ["/run.log"] = "kicked:place_closed" } } }),
				predicates {},
				options {}
			)
			check:expect(selection.reason):toEqual(REASONS.halted)
			check:expect(selection.halt):toEqual "kicked:place_closed"
			check:expect(selection.reference):toEqual ""
		end)

		suite:case("names a truncated record when the deadline passes with a defect", function(check)
			local selection = Roblox.observeScenario(
				deps({}, { steps = { { ["/run.log"] = "ARMED RESULTS TRUNCATED" } } }),
				predicates {},
				options { deadlineSeconds = 2 }
			)
			check:expect(selection.reason):toEqual(REASONS.truncated)
			check:expect(selection.defect):toEqual "truncated_record"
			check:expect(selection.reference):toEqual "/run.log"
		end)

		suite:case("names an unobserved boot when the deadline passes with no workload marker", function(check)
			local selection = Roblox.observeScenario(
				deps({}, { steps = { { ["/run.log"] = "RESULTS place=1" } } }),
				predicates {},
				options { deadlineSeconds = 2 }
			)
			check:expect(selection.reason):toEqual(REASONS.unobserved)
			check:expect(selection.reference):toEqual "/run.log"
		end)

		suite:case("names a missing receipt when the workload was observed but never summarised", function(check)
			local selection = Roblox.observeScenario(
				deps({}, { steps = { { ["/run.log"] = "ARMED RESULTS" } } }),
				predicates {},
				options { deadlineSeconds = 2 }
			)
			check:expect(selection.reason):toEqual(REASONS.missing)
		end)

		suite:case("names an unobserved boot when the deadline passes with no bound source at all", function(check)
			local selection = Roblox.observeScenario(deps({}, {}), predicates {}, options { deadlineSeconds = 2 })
			check:expect(selection.reason):toEqual(REASONS.unobserved)
			check:expect(selection.reference):toEqual ""
		end)

		suite:case("refuses two bound sources at the deadline", function(check)
			local selection = Roblox.observeScenario(
				deps({}, { steps = { { ["/a.log"] = "place=1", ["/b.log"] = "place=1" } } }),
				predicates {},
				options { deadlineSeconds = 2 }
			)
			check:expect(selection.reason):toEqual(REASONS.ambiguous)
		end)

		suite:case("refuses a driver that would not start", function(check)
			local selection = Roblox.observeScenario(deps({}, { started = false }), predicates {}, options {})
			check:expect(selection.reason):toEqual(REASONS.startFailed)
		end)

		suite:case("refuses a driver whose start threw, keeping the detail", function(check)
			local selection = Roblox.observeScenario(deps({}, { startFails = true }), predicates {}, options {})
			check:expect(selection.reason):toEqual(REASONS.startFailed)
			check:expect(string.find(selection.defect :: string, "driver refused", 1, true) ~= nil):toEqual(true)
		end)

		suite:case("refuses a census the host could not take", function(check)
			local selection = Roblox.observeScenario(deps({}, { listFails = true }), predicates {}, options {})
			check:expect(selection.reason):toEqual(REASONS.listFailed)
			check:expect(selection.defect):toEqual "list refused"
		end)

		suite:case("refuses a clock that does not report a finite reading", function(check)
			local selection = Roblox.observeScenario(deps({}, { clockFails = true }), predicates {}, options {})
			check:expect(selection.reason):toEqual(REASONS.clockFailed)
		end)

		suite:case("refuses a wait the host would not honour", function(check)
			local selection = Roblox.observeScenario(deps({}, { waitFails = true }), predicates {}, options {})
			check:expect(selection.reason):toEqual(REASONS.waitFailed)
		end)

		suite:case("refuses a selected source that could not be read back", function(check)
			local sources: Sources = {}
			local bound = deps({}, { steps = { { ["/run.log"] = "ARMED RESULTS SUMMARY" } } })
			local reads = 0
			local wrapped: Roblox.ScenarioDeps = {
				start = bound.start,
				list = bound.list,
				read = function(reference: string): string?
					reads += 1
					if reads > 1 and sources[reference] == nil then
						return nil
					end
					return bound.read(reference)
				end,
				now = bound.now,
				wait = bound.wait,
			}
			local selection = Roblox.observeScenario(wrapped, predicates {}, options {})
			check:expect(selection.reason):toEqual(REASONS.readFailed)
		end)

		suite:case("carries caller reason names instead of the defaults", function(check)
			local named: Roblox.ScenarioReasons = {
				startFailed = "launch_failed",
				listFailed = "log_list_failed",
				clockFailed = "clock_failed",
				waitFailed = "wait_failed",
				readFailed = "log_read_failed",
				ambiguous = "ambiguous_log",
				halted = "admission_refused",
				truncated = "receipt_truncated",
				unobserved = "boot_unobserved",
				missing = "receipt_missing",
			}
			local selection = Roblox.observeScenario(
				deps({}, { steps = { { ["/run.log"] = "ARMED RESULTS" } } }),
				predicates {},
				options { deadlineSeconds = 2, reasons = named }
			)
			check:expect(selection.reason):toEqual "receipt_missing"
		end)
	end)
end
