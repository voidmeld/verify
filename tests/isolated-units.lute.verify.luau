--!strict

local Core = require "../src/core"
local Units = require "../src/runtime/isolated-units"

local function unit(id: string, seconds: number?): Core.PlanUnit
	return { id = id, locator = id, tags = {}, requires = {}, weight = 1, deadlineSeconds = seconds }
end

local function skipped(id: string): Core.Report
	return Core.syntheticReport {
		executor = "fixture",
		environment = {},
		capabilities = {},
		id = id,
		name = "fixture",
		status = "skipped",
		skipReason = "not applicable",
	}
end

return function(harness: Core.Harness)
	harness:suite("isolated unit execution", function()
		harness:case("dispatches one unit at a time and continues after an enforced timeout", function(check)
			local events: { string } = {}
			local report = Units.run(
				{ id = "batch", index = 1, units = { unit("hung", nil), unit("next", 240) } },
				function(batch)
					local source = batch.units[1].locator
					table.insert(events, "dispatch " .. source)
					check:expect(#batch.units):toEqual(1)
					check:expect(batch.deadlineSeconds):toEqual(if source == "hung" then 180 else 240)
					if source == "hung" then
						return { status = "timed_out", detail = "watchdog killed worker" }
					end
					return { status = "returned", report = skipped "next" }
				end,
				{
					deadlineSeconds = 180,
					executor = "fixture",
					environment = { host = "fixture" },
					progress = function(line)
						table.insert(events, line)
					end,
				}
			)
			check:expect(events):toEqual { "running hung", "dispatch hung", "running next", "dispatch next" }
			check:expect(report.timedOut):toEqual(1)
			check:expect(report.skipped):toEqual(1)
			check:expect(report.results[1].failures[1].message):toEqual "exceeded 180s"
		end)
		harness:case("preserves repeated fixture failures under distinct result ids", function(check)
			local report = Units.run(
				{ id = "batch", index = 1, units = { unit("first", nil), unit("second", nil) } },
				function(batch)
					local result = skipped "shared fixture"
					if batch.index == 2 then
						result = Core.syntheticReport {
							executor = "fixture",
							environment = {},
							capabilities = {},
							id = "shared fixture",
							name = "fixture",
							status = "failed",
							message = "fixture broke",
						}
					end
					return { status = "returned", report = result }
				end,
				{ deadlineSeconds = 10, executor = "fixture", environment = {} }
			)
			check:expect(report.failed):toEqual(1)
			check:expect(report.skipped):toEqual(1)
			check:expect(report.results[2].id):toEqual "second:shared fixture"
			check:expect(report.results[2].failures[1].message):toEqual "fixture broke"
		end)
		harness:case("retains host failure detail without inventing a successful report", function(check)
			local report = Units.run({ id = "batch", index = 1, units = { unit("missing", nil) } }, function()
				return { status = "faulted", detail = "worker exited without a report" }
			end, { deadlineSeconds = 10, executor = "fixture", environment = {} })
			check:expect(report.failed):toEqual(1)
			check:expect(report.results[1].id):toEqual "unit:missing:execution"
			check:expect(report.results[1].failures[1].message):toEqual "worker exited without a report"
		end)
	end)
end
