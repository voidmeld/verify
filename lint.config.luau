--!strict

return {
	lute = {
		lint = {
			ignores = {
				"build/**",
				".lute/**",
			},
			globals = {},
			rulepaths = {
				"src/checks/lint-rules/global_table_usage.luau",
				"src/checks/lint-rules/type_check_inside_call.luau",
				"src/checks/lint-rules/bad_string_escape.luau",
			},
			ruleconfigs = {
				global_table_usage = {
					options = {
						allow = { "src/lute/chunk.luau", "src/lute/loader.luau", "tests/loader.lute.verify.luau" },
					},
				},
				global_function_in_scope = { off = true },
				unused_variable = { off = true },
			},
		},
	},
}
