--!strict

local Core = require "../src/core"

return function(harness: Core.Harness)
	harness:suite("source corpus accounting", function()
		harness:case("selects eligible names in locator order without replacing or mutating sources", function(check)
			local late = { name = "second.spec", path = "Root.Z", eligible = true, value = 2 }
			local early = { name = "first.spec", path = "Root.A", eligible = true, value = 1 }
			local sources = {
				late,
				{ name = "helper", path = "Root.Helper", eligible = true, value = 3 },
				{ name = "not-a-module.spec", path = "Root.NotModule", eligible = false, value = 4 },
				early,
			}
			local selected = Core.sourceCorpus.select(sources, function(source)
				return { name = source.name, path = source.path, eligible = source.eligible }
			end, "%.spec$")
			check:expect(#selected):toEqual(2)
			check:expect(selected[1] == early):toEqual(true)
			check:expect(selected[2] == late):toEqual(true)
			check:expect(sources[1] == late):toEqual(true)
			check:expect(selected[1].value):toEqual(1)
		end)
		harness:case("binds a stable manifest to the supplied corpus id and exact locators", function(check)
			local paths = { "Root.Z", "Root.A" }
			local seen = Core.sourceCorpus.manifest("mounted-specs", paths)
			check:expect(seen.count):toEqual(2)
			check:expect(seen.schemaVersion):toEqual(1)
			check:expect(seen.digest):toEqual(Core.planDigest {
				schemaVersion = 1,
				id = "mounted-specs",
				units = {
					{ id = "Root.A", locator = "Root.A", group = "Root.A" },
					{ id = "Root.Z", locator = "Root.Z", group = "Root.Z" },
				},
				policy = { caseIdStyle = "bare" },
			})
			check
				:expect(Core.sourceCorpus.manifest("mounted-specs", { "Root.A", "Root.Z" }).digest)
				:toEqual(seen.digest)
			check:expect(Core.sourceCorpus.manifest("other-specs", paths).digest == seen.digest):toEqual(false)
			check:expect(Core.sourceCorpus.manifest("mounted-specs", { "Root.A" }).digest == seen.digest):toEqual(false)
			check:expect(paths[1]):toEqual "Root.Z"
			check:expect(Core.sourceCorpus.manifest("empty", {}).count):toEqual(0)
		end)
		harness:case("does not credit an unreported source or infer coverage from unrelated results", function(check)
			local report = Core.syntheticReport {
				executor = "fixture",
				environment = {},
				capabilities = {},
				id = "named-case",
				name = "fixture",
				status = "failed",
				message = "fixture failed",
			}
			check:expect(Core.sourceCorpus.unreported({ "Root.A", "Root.Z" }, report)):toEqual { "Root.A", "Root.Z" }
			report.results[1].source = "Root.Z"
			check:expect(Core.sourceCorpus.unreported({ "Root.A", "Root.Z" }, report)):toEqual { "Root.A" }
			check:expect(report.failed):toEqual(1)
			check:expect(report.results[1].failures[1].message):toEqual "fixture failed"
		end)
	end)
end
