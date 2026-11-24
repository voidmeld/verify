--!strict

return {
	package = {
		name = "voidmeld/verify",
		version = "0.1.1",
		files = {
			"/src/**",
			"/tools/**",
			"/docs/**",
			"/.agents/skills/verify/**",
			"/README.md",
			"/CHANGELOG.md",
			"/LICENSE",
			"/PROVENANCE.md",
		},
		metadata = {
			description = "A test library for Luau and Roblox: cases, assertions, a simulated engine, hosts and reports.",
			license = "MIT",
			repository = "https://github.com/voidmeld/verify",
			exports = {
				Core = "src/core",
				Bdd = "src/bdd.luau",
				Roblox = "src/roblox",
				Lute = "src/lute",
				Codec = "src/codec",
				Gate = "src/gate",
				Evidence = "src/evidence",
				Benchmark = "src/benchmark.luau",
				Consumer = "src/consumer",
				AgentEval = "src/agent-eval",
				Checks = "src/checks",
			},
		},
		dependencies = {},
	},
}
