--!strict

local Core = require "../src/core"
local Gate = require "../src/gate"
local Suite = require "../src/runtime/spec-suite"

local function plan(): Core.PlanDraft
	return {
		id = "suite",
		units = {
			{ id = "first", locator = "tests/first.luau", group = "together" },
			{ id = "second", locator = "tests/second.luau", group = "together", deadlineSeconds = 7 },
			{ id = "third", locator = "tests/third.luau" },
		},
		policy = { caseIdStyle = "bare" },
	}
end

return function(harness: Core.Harness)
	harness:suite("spec suite gate preparation", function()
		harness:case("keeps exact file selection and valued gate flags out of the corpus", function(check)
			local invocation = Suite.parse {
				"tests/first.luau",
				"--case",
				"chosen",
				"--tier",
				"fast",
				"--shards=2",
				"--verbose",
				"--verdicts=results.txt",
				"--spec-deadline=tests/first.luau:11",
			}
			check:expect(invocation.specs["chosen"]):toEqual(nil)
			check:expect(invocation.specs["fast"]):toEqual(nil)
			check:expect(invocation.shards):toEqual(2)
			check:expect(invocation.verbose):toEqual(true)
			check:expect(invocation.verdictPath):toEqual "results.txt"
			local original = plan()
			local selected, gate, flags = Suite.prepare(original, invocation, {
				worker = "worker.luau",
				workers = 2,
				batches = 2,
				silent = { "tests/second.luau" },
				deadlineSeconds = 30,
			})
			check:expect(original.units[1].deadlineSeconds):toEqual(nil)
			check:expect(selected.units[1].deadlineSeconds):toEqual(11)
			check:expect(selected.units[2].deadlineSeconds):toEqual(7)
			check:expect(gate.id):toEqual "suite-focused"
			check:expect(flags):toEqual { "--case", "chosen", "--tier", "fast", "--file", "tests/first.luau" }
			local defined = Gate.define(gate)
			check:expect(defined.policy.concurrency):toEqual(2)
			check:expect(#gate.producers):toEqual(2)
		end)
		harness:case("rejects malformed and unknown per-spec deadlines", function(check)
			for _, flag in { "--spec-deadline=tests/first.luau:0", "--spec-deadline=broken" } do
				local ok = pcall(Suite.parse, { flag })
				check:expect(ok):toEqual(false)
			end
			local ok = pcall(Suite.prepare, plan(), Suite.parse { "--spec-deadline=absent:10" }, {
				worker = "worker.luau",
				workers = 1,
				batches = 1,
			})
			check:expect(ok):toEqual(false)
		end)
		harness:case("retains serial defaults and forwards unknown flags for gate refusal", function(check)
			local invocation = Suite.parse({ "--unknown", "--only", "specs" }, { serial = true, shards = 3 })
			check:expect(invocation.serial):toEqual(true)
			check:expect(invocation.shards):toEqual(3)
			check:expect(invocation.gateFlags):toEqual { "--unknown", "--only", "specs" }
			local _, gate = Suite.prepare(plan(), invocation, { worker = "worker.luau", workers = 1, batches = 1 })
			check:expect(gate.id):toEqual "suite"
		end)
	end)
end
