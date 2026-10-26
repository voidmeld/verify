--!strict

local Policy = require "./checks-policy"
local Repository = require "../src/checks/repository"
local Clone = require "../src/checks/clean-clone"
local Comments = require "../src/checks/comments"
local Manifest = require "../src/checks/manifest"
local Provenance = require "../src/checks/provenance"
local Surface = require "../src/checks/surface"
local packages = {
	{
		prefix = "Core",
		entry = "src/core/init.luau",
		load = function(): unknown
			return require "../src/core"
		end,
	},
	{
		prefix = "Lute",
		entry = "src/lute/init.luau",
		load = function(): unknown
			return require "../src/lute"
		end,
	},
	{
		prefix = "Roblox",
		entry = "src/roblox/init.luau",
		load = function(): unknown
			return require "../src/roblox"
		end,
	},
	{
		prefix = "Gate",
		entry = "src/gate/init.luau",
		load = function(): unknown
			return require "../src/gate"
		end,
	},
	{
		prefix = "Evidence",
		entry = "src/evidence/init.luau",
		load = function(): unknown
			return require "../src/evidence"
		end,
	},
	{
		prefix = "Consumer",
		entry = "src/consumer/init.luau",
		load = function(): unknown
			return require "../src/consumer"
		end,
	},
	{
		prefix = "AgentEval",
		entry = "src/agent-eval/init.luau",
		load = function(): unknown
			return require "../src/agent-eval"
		end,
	},
	{
		prefix = "Bdd",
		entry = "src/bdd.luau",
		load = function(): unknown
			return require "../src/bdd"
		end,
	},
	{
		prefix = "Benchmark",
		entry = "src/benchmark.luau",
		load = function(): unknown
			return require "../src/benchmark"
		end,
	},
	{
		prefix = "Checks",
		entry = "src/checks/init.luau",
		load = function(): unknown
			return require "../src/checks"
		end,
	},
}

local config: {
	boundary: Repository.Boundary,
	leakage: Repository.Scan,
	provenance: Provenance.Config,
	comments: Comments.Config,
	manifest: Manifest.Config,
	publicSurface: Surface.Config,
	cleanClone: Clone.Config,
} =
	{
		boundary = {
			root = "src/core",
			allowEmpty = true,
			rules = {
				{ pattern = "@std/", plain = true, why = "forbidden core token" },
				{ pattern = "@lute/", plain = true, why = "forbidden core token" },
				{ pattern = "game", plain = true, why = "forbidden core token" },
				{ pattern = "script", plain = true, why = "forbidden core token" },
				{ pattern = "Instance", plain = true, why = "forbidden core token" },
				{ pattern = "task.", plain = true, why = "forbidden core token" },
				{ pattern = "process", plain = true, why = "forbidden core token" },
				{ pattern = "filesystem", plain = true, why = "forbidden core token" },
			},
		},
		leakage = {
			suffixes = { ".luau", ".lua", ".md", ".json", ".toml", ".txt", ".yml", ".yaml" },
			exclude = { [Policy.selfPath] = true, LICENSE = true },
			rules = Policy.leakage,
			allowedLiterals = Policy.allowedLiterals,
		},
		provenance = {
			forbiddenPaths = {
				"vendor",
				"packages",
				"node_modules",
				"COPYING",
				"NOTICE",
				"package.json",
				"pesde.toml",
				"wally.toml",
			},
			license = "LICENSE",
			licenseFragments = {
				"MIT License",
				"Copyright (c) 2026 voidmeld",
				"Permission is hereby granted, free of charge, to any person obtaining a copy",
				'THE SOFTWARE IS PROVIDED "AS IS"',
			},
			requiredText = { ["PROVENANCE.md"] = { "licensed under the MIT License" } },
		},
		comments = {
			roots = { "examples", "src", "tests", "tools" },
			files = { "lint.config.luau" },
			configFiles = { ".styluaignore", "rokit.toml", "stylua.toml" },
			allowed = { "^%-%-![A-Za-z]+", "^%-%-# selene" },
			lineDirectives = true,
		},
		manifest = { path = "tests/manifest.luau", rules = { { root = "tests", pattern = "%.verify%.luau$" } } },
		publicSurface = { docs = "docs/api.md", packages = packages },
		cleanClone = {
			prefix = "verify-clean-clone",
			command = { "lute", "run", "tools/gate.luau", "--tier", "static", "--tier", "behavior" },
		},
	}

return config
