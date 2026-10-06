--!strict

local Bdd = require "../src/bdd"
local Verify = require "../src/core"

return function(suite: Verify.Harness)
	suite:suite("BDD authoring", function()
		suite:case("preserves familiar authoring while delegating lifecycle to Verify", function(check)
			local tick = 0
			local harness = Verify.createHarness {
				now = function()
					tick += 0.001
					return tick
				end,
			}
			local bdd = Bdd.create(harness)
			local trace: { string } = {}
			bdd.describe("suite", function()
				bdd.beforeEach(function(own)
					table.insert(trace, "setup")
					own(function()
						table.insert(trace, "cleanup")
					end)
				end)
				bdd.it("case", function()
					bdd.expect(2 + 2):toBe(4)
					table.insert(trace, "case")
				end)
				bdd.afterEach(function()
					table.insert(trace, "teardown")
				end)
			end)
			local report = harness:run { executor = "test" }
			check:expect(report.passed):toEqual(1)
			check:expect(trace):toEqual { "setup", "case", "teardown", "cleanup" }
		end)

		suite:case("hands a spy through alongside the authoring verbs", function(check)
			local harness = Verify.createHarness { now = os.clock }
			local bdd = Bdd.create(harness)
			bdd.it("case", function()
				local collaborator = bdd.spy(function(name: string): string
					return "greeted " .. name
				end)
				bdd.expect(collaborator.fn "warder"):toBe "greeted warder"
				bdd.expect(collaborator.callCount()):toBe(1)
				bdd.expect(collaborator.lastArgs()):toEqual { "warder" }
			end)
			local report = harness:run { executor = "test" }
			check:expect(report.passed):toEqual(1)
			check:expect(report.failed):toEqual(0)
		end)

		suite:case("routes runtime and declared skips through Verify", function(check)
			local harness = Verify.createHarness { now = os.clock }
			local bdd = Bdd.create(harness)
			bdd.itSkip("declared", "not selected")
			bdd.it("runtime", function()
				bdd.skip "executor declined"
			end)
			local report = harness:run { executor = "test" }
			check:expect(report.skipped):toEqual(2)
		end)

		suite:case("carries case id, tags, requirements and limitations through the authoring surface", function(check)
			local harness = Verify.createHarness { now = os.clock }
			local bdd = Bdd.create(harness)
			bdd.it("reward is granted once", {
				id = "reward.once",
				tags = { "e2e" },
				requires = { "player" },
				limitations = { "single session" },
				run = function() end,
			})
			bdd.it("plain case", function() end)
			local report = harness:run { executor = "test", capabilities = { "player" } }
			check:expect(report.results[1].id):toEqual "reward.once"
			check:expect(report.results[1].limitations):toEqual { "single session" }
			check:expect(report.passed):toEqual(2)
			local missing = harness:run { executor = "test", capabilities = {} }
			check:expect(missing.results[1].status):toEqual "unsupported"
			check:expect(missing.results[1].missingCapabilities):toEqual { "player" }
		end)

		suite:case("one surface registers, loads sources, adopts load failures and formats the report", function(check)
			local surface = Bdd.surface {
				executor = "test",
				environment = { runtime = "test" },
				capabilities = { "local-luau" },
				ambientSource = "entry",
			}
			local good = surface.load("good.verify.luau", function()
				surface.describe("good", function()
					surface.it("passes", function()
						surface.expect(1):toBe(1)
					end)
				end)
			end)
			check:expect(good):toEqual(nil)
			local bad = surface.load("bad.verify.luau", function()
				error("cannot require", 0)
			end)
			check:expect(bad):toEqual "cannot require"
			local report = surface.run()
			check:expect(report.passed):toEqual(1)
			check:expect(report.failed):toEqual(1)
			local text = Bdd.formatFailures(report, "Suite")
			check:expect(text):toContain "Suite\n"
			check:expect(text):toContain "cannot require"
			check:expect(text):toContain "Tests:  1 passed, 1 failed, 0 skipped (2 total)"
			check:expect(Bdd.formatResults(report)):toContain "✓ good › passes"
			surface.reset()
		end)
	end)

	suite:suite("surface selection", function()
		local function populate(surface: Bdd.Surface)
			surface.load("alpha.verify.luau", function()
				surface.describe("inventory", function()
					surface.it("adds an item", { id = "inv.add", tags = { "fast" }, run = function() end })
					surface.it("drops an item", function() end)
				end)
			end)
			surface.load("beta.verify.luau", function()
				surface.it("renders a view", { id = "view.render", tags = { "slow" }, run = function() end })
			end)
		end

		local function surfaceWith(selection: Verify.Selection?): Bdd.Surface
			local surface = Bdd.surface {
				executor = "test",
				environment = { runtime = "test" },
				capabilities = {},
				ambientSource = "entry",
				selection = selection,
			}
			populate(surface)
			return surface
		end

		local function ranIds(report: Bdd.Report): { string }
			local ids: { string } = {}
			for _, result in report.results do
				if result.status ~= "skipped" then
					table.insert(ids, result.name)
				end
			end
			table.sort(ids)
			return ids
		end

		suite:case("selects at creation by id, source, tag, name and predicate", function(check)
			check:expect(ranIds(surfaceWith({ ids = { "inv.add" } }).run())):toEqual { "adds an item" }
			check:expect(ranIds(surfaceWith({ sources = { "beta.verify.luau" } }).run())):toEqual { "renders a view" }
			check:expect(ranIds(surfaceWith({ tags = { "slow" } }).run())):toEqual { "renders a view" }
			check
				:expect(ranIds(surfaceWith({ nameContains = "item" }).run()))
				:toEqual { "adds an item", "drops an item" }
			local byPredicate = surfaceWith {
				predicate = function(subject)
					return subject.source == "alpha.verify.luau" and subject.name == "drops an item"
				end,
			}
			check:expect(ranIds(byPredicate.run())):toEqual { "drops an item" }
			check:expect(surfaceWith(nil).run().total):toEqual(3)
		end)

		suite:case("changes the selection through the setter and clears it", function(check)
			local surface = Bdd.surface {
				executor = "test",
				environment = { runtime = "test" },
				capabilities = {},
				ambientSource = "entry",
			}
			populate(surface)
			surface.setSelection { nameContains = "render" }
			check:expect(ranIds(surface.run())):toEqual { "renders a view" }
			surface.setSelection(nil)
			check:expect(surface.run().total):toEqual(3)
			surface.setSelection { nameContains = "no such case" }
			check:expect(surface.run().total):toEqual(0)
		end)
	end)
end
