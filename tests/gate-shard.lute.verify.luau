--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Cli = require "../src/lute/gate-cli"
local Gate = require "../src/gate"

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

it("parses a shard and its weight files", function()
	local command = assert(Cli.parse { "--shard", "2/3", "--weights", "w.json", "--record-weights", "r.json" })
	local slot = assert(command.shard)
	expect(slot.index):toBe(2)
	expect(slot.count):toBe(3)
	expect(command.weights):toBe "w.json"
	expect(command.recordWeights):toBe "r.json"
	for _, bad in { "0/3", "4/3", "1/0", "two/3" } do
		local refused, problem = Cli.parse { "--shard", bad }
		expect(refused == nil and problem ~= nil):toBe(true)
	end
end)

it("assigns every selected producer and spec file to exactly one shard", function()
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
		expect(`{name} {seen[name]}`):toBe(`{name} 1`)
	end
	expect(seen.release == nil):toBe(true)
	expect(seen.specs == nil):toBe(true)
end)

it("balances measured weight across shards", function()
	local loads: { number } = {}
	for index = 1, 3 do
		loads[index] = Cli.shard(draft(), { index = index, count = 3 }, weights, {}).load
	end
	table.sort(loads)
	expect(loads[3]):toBe(100)
	expect(loads[1] >= 40):toBe(true)
end)

it("gives unmeasured work the median weight", function()
	local share = Cli.shard(draft(), { index = 1, count = 1 }, { producers = {}, files = {} }, { "fast", "full" })
	expect(#share.only):toBe(2)
	expect(#share.files):toBe(3)
	expect(share.load):toBe(5)
end)

it("records producer and spec file durations from an outcome", function()
	local measured = Cli.measured({ producers = { kept = 3 }, files = {} }, {
		{ id = "types", timed = true, durationMicros = 12_340_000 },
		{ id = "flaky", timed = false, durationMicros = 99_000_000 },
		{ id = "specs", timed = false, durationMicros = 1 },
	}, {
		{ source = "tests/a.verify.luau", durationMicros = 1_000_000 },
		{ source = "tests/a.verify.luau", durationMicros = 2_000_000 },
		{ source = "command:types", durationMicros = 5 },
	})
	expect(measured.producers.types):toBe(12.3)
	expect(measured.producers.kept):toBe(3)
	expect(measured.producers.flaky == nil):toBe(true)
	expect(measured.producers.specs == nil):toBe(true)
	expect(measured.files["tests/a.verify.luau"]):toBe(3)
	expect(measured.files["command:types"] == nil):toBe(true)
end)

it("keeps a producer with the producers it runs after", function()
	local dependent: Gate.Draft = {
		id = "dependent",
		producers = {
			{ id = "perf", kind = "command", argv = { "perf" }, tier = "full" },
			{ id = "perf-memory", kind = "command", argv = { "memory" }, tier = "full", after = { "perf" } },
			{ id = "build", kind = "command", argv = { "build" }, tier = "full" },
			{ id = "canary", kind = "command", argv = { "canary" }, tier = "full", after = { "build" } },
		},
	}
	local heavy: Cli.Weights = { producers = { perf = 50, ["perf-memory"] = 1, build = 50, canary = 1 }, files = {} }
	for index = 1, 2 do
		local share = Cli.shard(dependent, { index = index, count = 2 }, heavy, {})
		local has: { [string]: boolean } = {}
		for _, id in share.only do
			has[id] = true
		end
		expect(has.perf == has["perf-memory"]):toBe(true)
		expect(has.build == has.canary):toBe(true)
		expect(share.load):toBe(51)
	end
end)

it("keeps spec files with the spec files of the producers they run after", function()
	local linked: Gate.Draft = {
		id = "linked",
		producers = {
			{ id = "check-a", kind = "tests", argv = { "a" }, locators = { "check:a" } },
			{ id = "time-a", kind = "tests", argv = { "a" }, locators = { "time:a" }, after = { "check-a" } },
			{ id = "check-b", kind = "tests", argv = { "b" }, locators = { "check:b" } },
			{ id = "time-b", kind = "tests", argv = { "b" }, locators = { "time:b" }, after = { "check-b" } },
			{ id = "loose", kind = "tests", argv = { "loose" }, locators = { "loose:1", "loose:2" } },
		},
	}
	local measured: Cli.Weights = {
		producers = {},
		files = { ["check:a"] = 5, ["time:a"] = 40, ["check:b"] = 5, ["time:b"] = 30, ["loose:1"] = 1, ["loose:2"] = 1 },
	}
	local owner: { [string]: number } = {}
	local total = 0
	for index = 1, 2 do
		local share = Cli.shard(linked, { index = index, count = 2 }, measured, {})
		for _, file in share.files do
			owner[file] = index
		end
		total += share.load
	end
	expect(total):toBe(82)
	expect(owner["check:a"]):toBe(owner["time:a"])
	expect(owner["check:b"]):toBe(owner["time:b"])
	expect(owner["check:a"] ~= owner["check:b"]):toBe(true)
	expect(owner["loose:1"] ~= nil and owner["loose:2"] ~= nil):toBe(true)
end)

return nil
