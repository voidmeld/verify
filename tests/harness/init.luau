--!strict

local Bdd = require "../src/bdd"

export type Body = Bdd.Body

return Bdd.surface {
	executor = "verify-tests",
	environment = { runtime = "lute" },
	capabilities = {},
	ambientSource = "verify-tests",
}
