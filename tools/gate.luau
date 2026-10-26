--!strict

local process = require "@std/process"

local Gate = require "../src/gate"
local Lute = require "../src/lute"

local USAGE =
	"usage: lute run tools/gate.luau [--native] [--only producer]... [--tier name]... [--case id]... [--file spec]... [--name text] [--rerun] [--explain id] [--list]"
local DIRECTORY = ".lute/tmp/verify-gate"
local native = false
local flags: { string } = {}
for index = 2, #process.args do
	if process.args[index] == "--native" then
		native = true
	else
		table.insert(flags, process.args[index])
	end
end

for index = #flags, 2, -1 do
	if flags[index - 1] == "--tier" and flags[index] == "fast" then
		flags[index] = "static"
		table.insert(flags, index + 1, "--tier")
		table.insert(flags, index + 2, "behavior")
	end
end

if #flags == 0 then
	local status = process.run { "git", "status", "--porcelain" }
	if not status.ok or string.match(status.stdout, "%S") ~= nil then
		print "gate: full candidate requires a clean committed HEAD; use focused checks while editing, then commit locally before the full gate and push"
		process.exit(1)
	end
end

local function check(id: string, argv: { string }, tier: string): Gate.ProducerDraft
	return { id = id, kind = "command", argv = argv, tier = tier }
end

local specs = require "../tests/manifest"
assert(#specs > 0, "test corpus is empty: tests")
local MEMORY = "tests/memory.lute.verify.luau"
local shared: { string } = {}
for _, locator in specs do
	if locator ~= MEMORY then
		table.insert(shared, locator)
	end
end

local SOURCES = { "src", "tests", "tools", "examples", "lint.config.luau" }
local lsp: { string } = {
	"luau-lsp",
	"analyze",
	"--platform=standard",
	"--base-luaurc=.luaurc",
	"--ignore=**/.lute/**",
	"--ignore=**/build/**",
}
local lint: { string } = { "lute", "lint", "-c", "lint.config.luau" }
local format: { string } = { "stylua", "--check" }
for _, source in SOURCES do
	table.insert(lsp, source)
	table.insert(lint, source)
	table.insert(format, source)
end

local producers: { Gate.ProducerDraft } = {
	check("test-manifest", { "lute", "run", "tools/check-test-manifest.luau" }, "static"),
	check("leakage", { "lute", "run", "tools/check-leakage.luau" }, "static"),
	check("public-surface", { "lute", "run", "tools/check-public-surface.luau" }, "static"),
	{
		id = "clean-clone",
		kind = "command",
		argv = { "lute", "run", "tools/check-clean-clone.luau" },
		exclusive = true,
		tier = "slow",
		deadlineSeconds = 1800,
		why = "a fresh clone of HEAD passes the portable tiers without working-tree state",
	},
	check("type-policy", { "lute", "run", "tools/check-no-any.luau" }, "static"),
	check("format", format, "static"),
	check("lint", lint, "static"),
	check("types", lsp, "static"),
	check("test-bootstrap", { "lute", "run", "tools/check-test-bootstrap.luau" }, "behavior"),
	{
		id = "specs",
		kind = "tests",
		worker = "tests/worker.luau",
		locators = shared,
		tier = "behavior",
		why = "the repository's own spec corpus",
		deadlineSeconds = 1800,
	},
	{
		id = "memory",
		kind = "tests",
		worker = "tests/worker.luau",
		locators = { MEMORY },
		isolate = true,
		tier = "behavior",
		why = "heap measurements need a process that no other spec shares",
		deadlineSeconds = 600,
	},
	check("example-experience", { "lute", "run", "examples/experience.luau" }, "behavior"),
	check("example-attachments", { "lute", "run", "examples/attachments.luau" }, "behavior"),
	check("example-quickstart", { "lute", "run", "examples/quickstart.luau" }, "behavior"),
	check("example-evidence", { "lute", "run", "examples/evidence-provenance.luau" }, "behavior"),
	check("example-multiplayer", { "lute", "run", "examples/multiplayer.luau", "simulator" }, "behavior"),
	check("example-benchmark", { "lute", "run", "examples/benchmark.luau" }, "behavior"),
	check("example-gate", { "lute", "run", "examples/gate.luau" }, "behavior"),
	check("example-agent-eval", { "lute", "run", "examples/agent-eval.luau" }, "behavior"),
	check(
		"consumer-diagnostics",
		{ "lute", "run", "tools/verify-check.luau", "--ruleset", "roblox", "examples" },
		"static"
	),
	check("boundary", { "lute", "run", "tools/check-boundary.luau" }, "static"),
	check("dependencies", { "lute", "run", "tools/check-dependencies.luau" }, "static"),
	check("provenance", { "lute", "run", "tools/check-provenance.luau" }, "static"),
	check("comments", { "lute", "run", "tools/check-code-comments.luau" }, "static"),
	{
		id = "native-conformance",
		kind = "native",
		argv = { "lute", "run", "tools/native-conformance.luau" },
		requires = { "native-studio" },
		tier = "native",
	},
	{
		id = "native-multiplayer",
		kind = "native",
		argv = { "lute", "run", "examples/multiplayer.luau" },
		requires = { "native-studio" },
		tier = "native",
	},
}

local deferrals: { [string]: string } = {}
if not native then
	deferrals["native-conformance"] = "the portable gate does not run the reference Studio host; use --native"
	deferrals["native-multiplayer"] = "the portable gate does not run the reference Studio host; use --native"
end

local exitCode = Lute.gate.cli(
	{
		id = "verify-gate",
		producers = producers,
		policy = { deferrals = deferrals, commandDeadlineSeconds = 900, deadlineSeconds = 3600 },
	},
	flags,
	{
		usage = USAGE,
		options = { directory = DIRECTORY, capabilities = if native then { "native-studio" } else {} },
	}
)
if exitCode ~= 0 then
	process.exit(exitCode)
end
