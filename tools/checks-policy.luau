--!strict

local Denylist = require "../src/checks/denylist"
export type Rule = Denylist.Rule

local productMaterial: { Rule } = {
	{ pattern = "rbxassetid://", why = "product asset identifier" },
	{ pattern = "rbxthumb://", why = "product asset identifier" },

	{ pattern = "%f[%w_]placeId%s*=%s*[1-9]", why = "product place identifier" },
	{ pattern = "%f[%w_]universeId%s*=%s*[1-9]", why = "product universe identifier" },
}

return {
	leakage = productMaterial,
	allowedLiterals = {
		["src/roblox/datatypes/font.luau"] = { 'rbxassetid://" .. tostring(id)' },
		["src/roblox/datatypes/misc.luau"] = { 'rbxassetid://" .. tostring(id)' },
		["tests/environment.verify.luau"] = { 'rbxassetid://1"' },
		["tests/fixtures/datatype-probes.json"] = {
			"rbxassetid://12187365364,",
			"rbxassetid://12,",
			"rbxassetid://1,",
			"rbxassetid://1}",
			"rbxassetid://1 |",
			"rbxassetid://5}",
		},
		["tests/fixtures/datatype-probes.luau"] = { "rbxassetid://1'" },
		["tests/place-runtime.lute.verify.luau"] = {
			"rbxassetid://123'",
			'rbxassetid://123"',
			'rbxassetid://1"',
			'rbxassetid://2"',
			"placeId = 2,",
			"universeId = 1,",
		},
		["tests/player-launcher.lute.verify.luau"] = { "placeId=123&", "placeId = 123," },
		["tests/progress.lute.verify.luau"] = { "placeId = 1," },
		["tests/reflection-snapshot.lute.verify.luau"] = { 'rbxassetid://1"' },
		["tests/script-context.lute.verify.luau"] = { "placeId = 2,", "universeId = 1," },
		["tests/studio-identity.lute.verify.luau"] = {
			"placeId = 123,",
			"universeId = 456 }",
			"placeId = 1 }",
			"placeId = 1,",
			"placeId = 1.5,",
			"placeId = 9007199254740992,",
			"universeId = 2,",
			"universeId = 2 }",
		},
		["tools/native-conformance.luau"] = { "placeId = 123,", "universeId = 456 }" },
	} :: { [string]: { string } },
	selfPath = "tools/checks-policy.luau",
}
