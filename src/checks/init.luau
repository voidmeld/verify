--!strict

local Repository = require "@self/repository"

return table.freeze {
	walk = require "@self/walk",
	temporaryDirectory = require "@self/temporary-directory",
	denylist = require "@self/denylist",
	cleanClone = require "@self/clean-clone",
	testManifest = require "@self/manifest",
	publicSurface = require "@self/surface",
	leakage = Repository.leakage,
	boundary = Repository.boundary,
	noAny = Repository.noAny,
	comments = require "@self/comments",
	provenance = require "@self/provenance",
	lintRules = table.freeze {
		globalTableUsage = require "@self/lint-rules/global_table_usage",
		typeCheckInsideCall = require "@self/lint-rules/type_check_inside_call",
		badStringEscape = require "@self/lint-rules/bad_string_escape",
	},
}
