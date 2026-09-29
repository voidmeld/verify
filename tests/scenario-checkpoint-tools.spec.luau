--!strict

local Verify = require "../src/core"
local Roblox = require "../src/roblox"

return function(suite: Verify.Harness)
	suite:suite("checkpoint planning and retained steps", function()
		suite:case("orders a complete checkpoint matrix and leaves route rows undriven", function(check)
			local route = { kind = "route", checkpoint = "end", viewport = "wide" }
			local first = { kind = "checkpoint", checkpoint = "first", viewport = "wide" }
			local second = { kind = "checkpoint", checkpoint = "first", viewport = "narrow" }
			local ordered, reason = Roblox.checkpointPlan.order(
				{ "first" },
				{ "wide", "narrow" },
				{ second, route, first }
			)
			check:expect(reason):toEqual(nil)
			check:expect((ordered :: any).driven[1]):toEqual(first)
			check:expect((ordered :: any).driven[2]):toEqual(second)
			check:expect((ordered :: any).undriven[1]):toEqual(route)
		end)

		suite:case("refuses missing and duplicate checkpoint rows", function(check)
			local row = { kind = "checkpoint", checkpoint = "first", viewport = "wide" }
			local missing, missingReason = Roblox.checkpointPlan.order({ "first" }, { "wide", "narrow" }, { row })
			check:expect(missing):toEqual(nil)
			check:expect(missingReason):toEqual "checkpoint_row_missing: first on narrow"
			local duplicate, duplicateReason = Roblox.checkpointPlan.order({ "first" }, { "wide" }, { row, row })
			check:expect(duplicate):toEqual(nil)
			check:expect(duplicateReason):toEqual "checkpoint_row_duplicate: first on wide"
		end)

		suite:case("collect-all leaves ordinary frame rows to the caller", function(check)
			local row = { kind = "route", checkpoint = "end", viewport = "wide" }
			local ordered, reason = Roblox.checkpointPlan.order({ "first" }, { "wide" }, { row }, true)
			check:expect(reason):toEqual(nil)
			check:expect(#(ordered :: any).driven):toEqual(0)
			check:expect(#(ordered :: any).undriven):toEqual(0)
		end)

		suite:case("retains failed outputs and excludes evidence-only calls", function(check)
			local stored: { [string]: string } = {}
			local journal = Roblox.scenarioStepJournal.create("session-1", {
				digest = function(bytes: string): string
					return "digest:" .. bytes
				end,
				write = function(path: string, bytes: string)
					stored[path] = bytes
				end,
			})
			journal:record({ kind = "poll", label = "first", tool = "execute", path = "first.txt", request = "ask" }, {
				ok = false,
				output = "refused",
			})
			journal:record({
				kind = "capture",
				label = "burst",
				tool = "capture",
				path = "burst.txt",
				request = "image",
				evidenceOnly = true,
			}, { ok = true, output = "saved" })
			check:expect(stored["first.txt"]):toEqual "refused"
			check:expect(journal.steps[1].ordinal):toEqual(1)
			check:expect(journal.steps[1].requestDigest):toEqual "digest:ask"
			check:expect(journal.steps[1].resultDigest):toEqual "digest:refused"
			check:expect(journal.steps[1].status):toEqual "failed"
			check:expect(journal.steps[2].ordinal):toEqual(2)
			check:expect(#journal.calls):toEqual(1)
			check:expect(journal.calls[1].binding):toEqual "session-1"
		end)
	end)
end
