--!strict

local fs = require "@std/fs"
local process = require "@std/process"
local Core = require "../src/core"
local Files = require "../src/lute/files"
local Platform = require "../src/lute/platform"
local Wire = require "../src/lute/wire"

return function(suite: Core.Harness)
	suite:suite("single platform execution", function()
		suite:case("simulator subprocess runs selected ordinary case and persists its report", {
			timeoutSeconds = 20,
			run = function(check: Core.Context)
				local root = Files.claimDirectory "/tmp/verify-platform-tests"
				check:defer(function()
					fs.removeDirectory(root, { recursive = true })
				end)
				local result = Platform.run {
					host = "simulator",
					entry = "examples/platform-entry.luau",
					caseIds = { "instance-state" },
					output = root,
					deadlineSeconds = 10,
				}
				check:expect(result.report.passed):toEqual(1)
				check:expect(result.report.results[1].id):toEqual "instance-state"
				check:expect(Wire.decode(fs.readFileToString(result.reportPath)).passed):toEqual(1)
			end,
		})
		suite:case("unknown and empty explicit selection fail instead of running all cases", {
			timeoutSeconds = 20,
			run = function(check: Core.Context)
				local root = Files.claimDirectory "/tmp/verify-platform-tests"
				check:defer(function()
					fs.removeDirectory(root, { recursive = true })
				end)
				local selections: { { string } } = { { "missing" }, {} }
				for _, ids in selections do
					local result = Platform.run {
						host = "simulator",
						entry = "examples/platform-entry.luau",
						caseIds = ids,
						output = root,
						deadlineSeconds = 10,
					}
					check:expect(result.report.failed):toEqual(1)
					check:expect(result.report.passed):toEqual(0)
				end
			end,
		})
		suite:case("required absent media adds a failure and updates the persisted summary", {
			timeoutSeconds = 20,
			run = function(check: Core.Context)
				local root = Files.claimDirectory "/tmp/verify-platform-tests"
				check:defer(function()
					fs.removeDirectory(root, { recursive = true })
				end)
				local result = Platform.run {
					host = "simulator",
					entry = "examples/platform-entry.luau",
					output = root,
					deadlineSeconds = 10,
					requiredMedia = { "image/png" },
				}
				check:expect(result.report.passed):toEqual(1)
				check:expect(result.report.failed):toEqual(1)
				check:expect(Wire.decode(fs.readFileToString(result.reportPath)).failed):toEqual(1)
				local summary = fs.readFileToString(result.directory .. "/summary.txt")
				check:expect(summary):toContain "required durable evidence missing"
				check:expect(summary):toContain "1 failed"
			end,
		})
		suite:case("nonyielding simulator is killed by the parent deadline", {
			timeoutSeconds = 15,
			run = function(check: Core.Context)
				local root = Files.claimDirectory "/tmp/verify-platform-tests"
				check:defer(function()
					fs.removeDirectory(root, { recursive = true })
				end)
				local fixture = Files.claimDirectory(tostring(process.cwd()) .. "/.verify-platform-fixtures")
				check:defer(function()
					fs.removeDirectory(fixture, { recursive = true })
				end)
				local entry = fixture .. "/spin.luau"
				fs.writeStringToFile(
					entry,
					"return function() return { cases = { { id = 'spin', name = 'spin', run = function() while true do end end } }, now = os.clock, options = { executor = 'spin' } } end"
				)
				local result = Platform.run {
					host = "simulator",
					entry = entry,
					output = root,
					deadlineSeconds = 1,
				}
				check:expect(result.report.timedOut):toEqual(1)
				check:expect(Wire.decode(fs.readFileToString(result.reportPath)).timedOut):toEqual(1)
				check:expect(fs.exists(result.directory .. "/summary.txt")):toEqual(true)
			end,
		})
		suite:case("runCases selects exactly requested cases and closes the host once", function(check)
			local executed: { string } = {}
			local closed = 0
			local deferred = 0
			local cases: { Core.NamedCase } = {
				{
					id = "first",
					name = "first",
					run = function()
						table.insert(executed, "first")
					end,
				},
				{
					id = "second",
					name = "second",
					run = function(context: Core.Context)
						table.insert(executed, "second")
						context:defer(function()
							deferred += 1
						end)
					end,
				},
			}
			local report = Core.runCases(cases, {
				executor = "selection",
				bind = function(): Core.CaseHost
					return {
						name = "fixture",
						capabilities = {},
						environment = {},
						now = os.clock,
						invoke = function(): unknown
							return nil
						end,
						close = function()
							closed += 1
						end,
					}
				end,
			}, os.clock, { "second" })
			check:expect(report.total):toEqual(1)
			check:expect(executed):toEqual { "second" }
			check:expect(closed):toEqual(1)
			check:expect(deferred):toEqual(1)
		end)
		suite:case("runCases rejects unknown, duplicate and empty ids before executing", function(check)
			local calls = 0
			local spec: Core.NamedCase = {
				id = "known",
				name = "known",
				run = function()
					calls += 1
				end,
			}
			local selections: { { string } } = { { "missing" }, { "known", "known" }, {} }
			for _, ids in selections do
				local ok = pcall(Core.runCases, { spec }, { executor = "selection" }, os.clock, ids)
				check:expect(ok):toEqual(false)
			end
			local duplicate = pcall(Core.runCases, { spec, spec }, { executor = "selection" }, os.clock)
			check:expect(duplicate):toEqual(false)
			check:expect(calls):toEqual(0)
		end)
	end)
end
