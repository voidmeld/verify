--!strict

local Cli = require "../src/lute/gate-cli"
local Gate = require "../src/gate"
local Verify = require "../src/core"

return function(suite: Verify.Harness)
	local function draft(): Gate.Draft
		return {
			id = "sharded",
			producers = {
				{ id = "types", kind = "command", argv = { "types" }, tier = "full" },
				{ id = "format", kind = "command", argv = { "format" }, tier = "fast" },
				{ id = "release", kind = "command", argv = { "release" }, tier = "release" },
				{
					id = "specs",
					kind = "tests",
					argv = { "specs" },
					tier = "fast",
					locators = { "tests/a.verify.luau", "tests/b.verify.luau", "tests/c.verify.luau" },
				},
			},
		}
	end

	local weights: Cli.Weights = {
		producers = { types = 90, format = 10 },
		files = { ["tests/a.verify.luau"] = 100, ["tests/b.verify.luau"] = 40, ["tests/c.verify.luau"] = 30 },
	}

	suite:case("parses a shard and its weight files", function(check)
		local command = assert(Cli.parse { "--shard", "2/3", "--weights", "w.json", "--record-weights", "r.json" })
		local slot = assert(command.shard)
		check:expect(slot.index):toBe(2)
		check:expect(slot.count):toBe(3)
		check:expect(command.weights):toBe "w.json"
		check:expect(command.recordWeights):toBe "r.json"
		for _, bad in { "0/3", "4/3", "1/0", "two/3" } do
			local refused, problem = Cli.parse { "--shard", bad }
			check:expect(refused == nil and problem ~= nil):toBe(true)
		end
	end)

	suite:case("assigns every selected producer and spec file to exactly one shard", function(check)
		local seen: { [string]: number } = {}
		for index = 1, 3 do
			local share = Cli.shard(draft(), { index = index, count = 3 }, weights, { "fast", "full" })
			for _, id in share.only do
				seen[id] = (seen[id] or 0) + 1
			end
			for _, file in share.files do
				seen[file] = (seen[file] or 0) + 1
			end
		end
		for _, name in { "types", "format", "tests/a.verify.luau", "tests/b.verify.luau", "tests/c.verify.luau" } do
			check:expect(`{name} {seen[name]}`):toBe(`{name} 1`)
		end
		check:expect(seen.release == nil):toBe(true)
		check:expect(seen.specs == nil):toBe(true)
	end)

	suite:case("balances measured weight across shards", function(check)
		local loads: { number } = {}
		for index = 1, 3 do
			loads[index] = Cli.shard(draft(), { index = index, count = 3 }, weights, {}).load
		end
		table.sort(loads)
		check:expect(loads[3]):toBe(100)
		check:expect(loads[1] >= 40):toBe(true)
	end)

	suite:case("gives unmeasured work the median weight", function(check)
		local share = Cli.shard(draft(), { index = 1, count = 1 }, { producers = {}, files = {} }, { "fast", "full" })
		check:expect(#share.only):toBe(2)
		check:expect(#share.files):toBe(3)
		check:expect(share.load):toBe(5)
	end)

	suite:case("records producer and spec file durations from an outcome", function(check)
		local measured = Cli.measured({ producers = { kept = 3 }, files = {} }, {
			{ id = "types", timed = true, durationMicros = 12_340_000 },
			{ id = "flaky", timed = false, durationMicros = 99_000_000 },
			{ id = "specs", timed = false, durationMicros = 1 },
		}, {
			{ source = "tests/a.verify.luau", durationMicros = 1_000_000 },
			{ source = "tests/a.verify.luau", durationMicros = 2_000_000 },
			{ source = "command:types", durationMicros = 5 },
		})
		check:expect(measured.producers.types):toBe(12.3)
		check:expect(measured.producers.kept):toBe(3)
		check:expect(measured.producers.flaky == nil):toBe(true)
		check:expect(measured.producers.specs == nil):toBe(true)
		check:expect(measured.files["tests/a.verify.luau"]):toBe(3)
		check:expect(measured.files["command:types"] == nil):toBe(true)
	end)

	suite:case("keeps a producer with the producers it runs after", function(check)
		local dependent: Gate.Draft = {
			id = "dependent",
			producers = {
				{ id = "perf", kind = "command", argv = { "perf" }, tier = "full" },
				{ id = "perf-memory", kind = "command", argv = { "memory" }, tier = "full", after = { "perf" } },
				{ id = "build", kind = "command", argv = { "build" }, tier = "full" },
				{ id = "canary", kind = "command", argv = { "canary" }, tier = "full", after = { "build" } },
			},
		}
		local heavy: Cli.Weights =
			{ producers = { perf = 50, ["perf-memory"] = 1, build = 50, canary = 1 }, files = {} }
		for index = 1, 2 do
			local share = Cli.shard(dependent, { index = index, count = 2 }, heavy, {})
			local has: { [string]: boolean } = {}
			for _, id in share.only do
				has[id] = true
			end
			check:expect(has.perf == has["perf-memory"]):toBe(true)
			check:expect(has.build == has.canary):toBe(true)
			check:expect(share.load):toBe(51)
		end
	end)
end
