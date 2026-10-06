--!strict

local fs = require "@std/fs"
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

local function check(id: string, argv: { string }, tier: string): Gate.ProducerDraft
	return { id = id, kind = "command", argv = argv, tier = tier }
end

local specs = Lute.corpus.discover {
	listDir = fs.listDirectory,
	rules = { { root = "tests", pattern = "%.spec%.luau$" } },
}
assert(#specs > 0, "test corpus is empty: tests")
local luneSpecs = Lute.corpus.discover {
	listDir = fs.listDirectory,
	rules = { { root = "tests/lune", pattern = "%.lune%-test%.luau$" } },
}
assert(#luneSpecs > 0, "lune test corpus is empty: tests/lune")

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
	check("type-policy", { "lute", "run", "tools/check-no-any.luau" }, "static"),
	check("format", format, "static"),
	check("lint", lint, "static"),
	check("types", lsp, "static"),
	check("test-bootstrap", { "lute", "run", "tools/check-test-bootstrap.luau" }, "behavior"),
	{
		id = "specs",
		kind = "tests",
		worker = "examples/worker.luau",
		locators = specs,
		tier = "behavior",
		why = "the repository's own spec corpus",
		deadlineSeconds = 1800,
	},
	check("reflection", { "lune", "run", "tools/check-reflection.luau" }, "behavior"),
	check("example-experience", { "lute", "run", "examples/experience.luau" }, "behavior"),
	{
		id = "lune-specs",
		kind = "tests",
		worker = "tools/lune-worker.luau",
		command = { "lune", "run" },
		locators = luneSpecs,
		tier = "behavior",
		why = "the Lune host's spec corpus, run in real lune processes",
		deadlineSeconds = 1800,
	},
	check("example-quickstart", { "lute", "run", "examples/quickstart.luau" }, "behavior"),
	check("example-lune-fixture", { "lune", "run", "examples/lune-fixture.luau" }, "behavior"),
	check("example-lune-run", { "lune", "run", "examples/lune-run.luau" }, "behavior"),
	check("example-evidence-lute", { "lute", "run", "examples/evidence-provenance/lute.luau" }, "behavior"),
	check("example-evidence-lune", { "lune", "run", "examples/evidence-provenance/lune.luau" }, "behavior"),
	check("example-multiplayer", { "lute", "run", "examples/multiplayer.luau", "simulator" }, "behavior"),
	check("example-benchmark", { "lute", "run", "examples/benchmark.luau" }, "behavior"),
	check("example-gate", { "lute", "run", "examples/gate.luau" }, "behavior"),
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
