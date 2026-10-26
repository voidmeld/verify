--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local temporary = require "./temporary"

local fs = require "@std/fs"
local process = require "@std/process"
local Core = require "../src/core"
local Files = require "../src/lute/files"
local Platform = require "../src/lute/platform"
local Wire = require "../src/lute/wire"

describe("single platform execution", function()
	it("simulator subprocess runs selected ordinary case and persists its report", {
		timeoutSeconds = 20,
		run = function(_, caseContext)
			local root = temporary(caseContext, "verify-platform-tests")
			local result = Platform.run {
				host = "simulator",
				entry = "examples/platform-entry.luau",
				caseIds = { "instance-state" },
				output = root,
				deadlineSeconds = 10,
			}
			expect(result.report.passed):toEqual(1)
			expect(result.report.results[1].id):toEqual "instance-state"
			expect(Wire.decode(fs.readFileToString(result.reportPath)).passed):toEqual(1)
		end,
	})
	it("unknown and empty explicit selection fail instead of running all cases", {
		timeoutSeconds = 20,
		run = function(_, caseContext)
			local root = temporary(caseContext, "verify-platform-tests")
			local selections: { { string } } = { { "missing" }, {} }
			for _, ids in selections do
				local result = Platform.run {
					host = "simulator",
					entry = "examples/platform-entry.luau",
					caseIds = ids,
					output = root,
					deadlineSeconds = 10,
				}
				expect(result.report.failed):toEqual(1)
				expect(result.report.passed):toEqual(0)
			end
		end,
	})
	it("required absent media adds a failure and updates the persisted summary", {
		timeoutSeconds = 20,
		run = function(_, caseContext)
			local root = temporary(caseContext, "verify-platform-tests")
			local result = Platform.run {
				host = "simulator",
				entry = "examples/platform-entry.luau",
				output = root,
				deadlineSeconds = 10,
				requiredMedia = { "image/png" },
			}
			expect(result.report.passed):toEqual(1)
			expect(result.report.failed):toEqual(1)
			expect(Wire.decode(fs.readFileToString(result.reportPath)).failed):toEqual(1)
			local summary = fs.readFileToString(result.directory .. "/summary.txt")
			expect(summary):toContain "required durable evidence missing"
			expect(summary):toContain "1 failed"
		end,
	})
	it("nonyielding simulator is killed by the parent deadline", {
		timeoutSeconds = 15,
		run = function(own, caseContext)
			local root = temporary(caseContext, "verify-platform-tests")
			local fixture = Files.claimDirectory(tostring(process.cwd()) .. "/.verify-platform-fixtures")
			own(function()
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
			expect(result.report.timedOut):toEqual(1)
			expect(Wire.decode(fs.readFileToString(result.reportPath)).timedOut):toEqual(1)
			expect(fs.exists(result.directory .. "/summary.txt")):toEqual(true)
		end,
	})
	it("runCases selects exactly requested cases and closes the host once", function()
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
		expect(report.total):toEqual(1)
		expect(executed):toEqual { "second" }
		expect(closed):toEqual(1)
		expect(deferred):toEqual(1)
	end)
	it("runCases rejects unknown, duplicate and empty ids before executing", function()
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
			expect(ok):toEqual(false)
		end
		local duplicate = pcall(Core.runCases, { spec, spec }, { executor = "selection" }, os.clock)
		expect(duplicate):toEqual(false)
		expect(calls):toEqual(0)
	end)
end)

return nil
