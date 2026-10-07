--!strict

local Verify = require "../src/core"
local Roblox = require "../src/roblox"

local ERRORS = { "attempt to", "refused", "Infinite yield", "not authorized", "Stack Begin" }

return function(suite: Verify.Harness)
	suite:suite("console classification", function()
		suite:case("classifies console lines by the supplied error patterns", function(check)
			local lines = {
				"12:00:01 loading stage one",
				"12:00:02 attempt to index nil with 'Engine'",
				"12:00:03 remote call refused",
				"12:00:04 Infinite yield possible on 'WaitForChild'",
				"12:00:05 player is not authorized to teleport",
				"12:00:06 Stack Begin",
				"12:00:07 all systems nominal",
			}
			local errorLines = Verify.classifyConsole(lines, { errorPatterns = ERRORS })
			check:expect(#errorLines):toEqual(5)
			check:expect(errorLines[1]):toEqual(lines[2])
			check:expect(errorLines[5]):toEqual(lines[6])
		end)

		suite:case("keeps only distinct error patterns matched, in source order", function(check)
			local lines = { "attempt to call a nil value", "totally fine", "refused: too many requests" }
			check:expect((Verify.classifyConsole(lines, { errorPatterns = ERRORS }))):toEqual { lines[1], lines[3] }
		end)

		suite:case("drops a matched line an adopter's own ignore pattern names", function(check)
			local lines = { "attempt to index nil with 'DebugOverlay'", "attempt to index nil with 'Engine'" }
			local errorLines =
				Verify.classifyConsole(lines, { errorPatterns = ERRORS, ignorePatterns = { "DebugOverlay" } })
			check:expect(errorLines):toEqual { lines[2] }
		end)

		suite:case("uses only the error patterns it is given", function(check)
			local lines = { "refused", "attempt to do a thing" }
			local errorLines = Verify.classifyConsole(lines, { errorPatterns = { "refused" } })
			check:expect(errorLines):toEqual { lines[1] }
		end)

		suite:case("refuses a classification without error patterns", function(check)
			assert(not pcall(Verify.classifyConsole, { "refused" }, {} :: Verify.ClassifyConsoleOptions))
		end)

		suite:case("exposes the Roblox console patterns as a frozen set", function(check)
			check:expect(table.isfrozen(Roblox.consolePatterns)):toBe(true)
			check
				:expect(
					#Verify.classifyConsole(
						{ "Infinite yield possible" },
						{ errorPatterns = Roblox.consolePatterns.errors }
					)
				)
				:toBe(1)
		end)

		suite:case("rejects a non-dense lines array", function(check)
			assert(not pcall(Verify.classifyConsole, { [1] = "a", [3] = "b" }, { errorPatterns = ERRORS }))
		end)

		suite:case("drops a matched line an adopter's own predicate names", function(check)
			local lines = { "refused: quota", "refused: unknown" }
			local errorLines = Verify.classifyConsole(lines, {
				errorPatterns = ERRORS,
				ignore = function(line: string): boolean
					return string.find(line, "quota", 1, true) ~= nil
				end,
			})
			check:expect(errorLines):toEqual { lines[2] }
		end)

		suite:case("matches without case when the adopter asks for it", function(check)
			local lines = { "REFUSED: quota", "all good" }
			check:expect((Verify.classifyConsole(lines, { errorPatterns = { "refused" } }))):toEqual {}
			check
				:expect((Verify.classifyConsole(lines, { errorPatterns = { "refused" }, caseInsensitive = true })))
				:toEqual { lines[1] }
		end)

		suite:case("attributes a trailing block to the line before it", function(check)
			local lines = {
				"harmless notice refused by policy",
				"Stack Begin",
				"Frame 1",
				"Stack End",
				"attempt to index nil with 'Engine'",
			}
			local errorLines = Verify.classifyConsole(lines, {
				errorPatterns = Roblox.consolePatterns.errors,
				ignorePatterns = { "harmless notice" },
				blockBeginPatterns = Roblox.consolePatterns.blockBegin,
				blockEndPatterns = Roblox.consolePatterns.blockEnd,
			})
			check:expect(errorLines):toEqual { lines[5] }
		end)

		suite:case("keeps a block whose preceding line is itself an error", function(check)
			local lines = { "attempt to index nil with 'Engine'", "Stack Begin", "Frame 1", "Stack End" }
			local errorLines = Verify.classifyConsole(lines, {
				errorPatterns = ERRORS,
				blockBeginPatterns = { "Stack Begin" },
				blockEndPatterns = { "Stack End" },
			})
			check:expect(errorLines):toEqual { lines[1], lines[2] }
		end)

		suite:case("keeps an unterminated block after an ignored line", function(check)
			local lines = { "harmless notice refused by policy", "Stack Begin", "Frame 1" }
			local errorLines = Verify.classifyConsole(lines, {
				errorPatterns = ERRORS,
				ignorePatterns = { "harmless notice" },
				blockBeginPatterns = { "Stack Begin" },
				blockEndPatterns = { "Stack End" },
			})
			check:expect(errorLines):toEqual { lines[2] }
		end)

		suite:case("refuses one half of a block pattern pair", function(check)
			assert(
				not pcall(
					Verify.classifyConsole,
					{ "a" },
					{ errorPatterns = ERRORS, blockBeginPatterns = { "Stack Begin" } }
				)
			)
		end)

		suite:case("splits console text on either line ending before classifying", function(check)
			local text = "loading\r\nattempt to index nil with 'Engine'\rall good\n"
			check
				:expect((Verify.splitConsoleLines(text)))
				:toEqual { "loading", "attempt to index nil with 'Engine'", "all good" }
			check
				:expect((Verify.classifyConsoleText(text, { errorPatterns = ERRORS })))
				:toEqual { "attempt to index nil with 'Engine'" }
		end)
	end)
end
