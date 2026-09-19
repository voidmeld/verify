--!strict

local process = require "@std/process"

local checks = {
	{ "stylua", "--check", "src", "tests", "tools", "examples", "lint.config.luau" },
	{ "lute", "lint", "-c", "lint.config.luau", "src", "tests", "tools", "examples" },
	{
		"luau-lsp",
		"analyze",
		"--platform=standard",
		"--base-luaurc=.luaurc",
		"--ignore=**/.lute/**",
		"--ignore=**/build/**",
		"src",
		"tests",
		"tools",
		"examples",
	},
	{ "lute", "test", "tests" },
	{ "lute", "run", "tools/verify-check.luau", "examples" },
	{ "lute", "run", "tools/check-boundary.luau" },
	{ "lute", "run", "tools/check-dependencies.luau" },
	{ "lute", "run", "tools/check-provenance.luau" },
	{ "lute", "run", "tools/check-code-comments.luau" },
}
local failed = 0
for _, command in checks do
	print("-> " .. table.concat(command, " "))
	local result = process.run(command)
	if result.stdout ~= "" then
		print(result.stdout)
	end
	if result.stderr ~= "" then
		print(result.stderr)
	end
	if not result.ok then
		failed += 1
	end
end
if failed > 0 then
	print(("gate: FAILED (%d checks)"):format(failed))
	process.exit(1)
end
print(("gate: PASSED (%d checks)"):format(#checks))
