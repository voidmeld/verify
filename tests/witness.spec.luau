--!strict

local test = require "@std/test"
local Verify = require "../src/core"

test.suite("console classification", function(suite)
	suite:case("classifies console lines by default error and ignore patterns", function(assert)
		local lines = {
			"12:00:01 loading zone one",
			"12:00:02 attempt to index nil with 'Engine'",
			"12:00:03 remote call refused",
			"12:00:04 Infinite yield possible on 'WaitForChild'",
			"12:00:05 player is not authorized to teleport",
			"12:00:06 Stack Begin",
			"12:00:07 all systems nominal",
		}
		local errorLines = Verify.classifyConsole(lines)
		assert.eq(#errorLines, 5)
		assert.eq(errorLines[1], lines[2])
		assert.eq(errorLines[5], lines[6])
	end)

	suite:case("keeps only distinct error patterns matched, in source order", function(assert)
		local lines = { "attempt to call a nil value", "totally fine", "refused: too many requests" }
		assert.eq(Verify.classifyConsole(lines), { lines[1], lines[3] })
	end)

	suite:case("drops a matched line an adopter's own ignore pattern names", function(assert)
		local lines = { "attempt to index nil with 'DebugOverlay'", "attempt to index nil with 'Engine'" }
		local errorLines = Verify.classifyConsole(lines, { ignorePatterns = { "DebugOverlay" } })
		assert.eq(errorLines, { lines[2] })
	end)

	suite:case("accepts a narrower error pattern set than the default", function(assert)
		local lines = { "refused", "attempt to do a thing" }
		local errorLines = Verify.classifyConsole(lines, { errorPatterns = { "refused" } })
		assert.eq(errorLines, { lines[1] })
	end)

	suite:case("rejects a non-dense lines array", function(assert)
		assert.that(not pcall(Verify.classifyConsole, { [1] = "a", [3] = "b" }))
	end)

	suite:case("drops a matched line an adopter's own predicate names", function(assert)
		local lines = { "refused: quota", "refused: unknown" }
		local errorLines = Verify.classifyConsole(lines, {
			ignore = function(line: string): boolean
				return string.find(line, "quota", 1, true) ~= nil
			end,
		})
		assert.eq(errorLines, { lines[2] })
	end)

	suite:case("matches without case when the adopter asks for it", function(assert)
		local lines = { "REFUSED: quota", "all good" }
		assert.eq(Verify.classifyConsole(lines, { errorPatterns = { "refused" } }), {})
		assert.eq(
			Verify.classifyConsole(lines, { errorPatterns = { "refused" }, caseInsensitive = true }),
			{ lines[1] }
		)
	end)

	suite:case("attributes a trailing block to the line before it", function(assert)
		local lines = {
			"harmless notice refused by policy",
			"Stack Begin",
			"Frame 1",
			"Stack End",
			"attempt to index nil with 'Engine'",
		}
		local errorLines = Verify.classifyConsole(lines, {
			ignorePatterns = { "harmless notice" },
			blockBeginPatterns = Verify.DEFAULT_WITNESS_BLOCK_BEGIN_PATTERNS,
			blockEndPatterns = Verify.DEFAULT_WITNESS_BLOCK_END_PATTERNS,
		})
		assert.eq(errorLines, { lines[5] })
	end)

	suite:case("keeps a block whose preceding line is itself an error", function(assert)
		local lines = { "attempt to index nil with 'Engine'", "Stack Begin", "Frame 1", "Stack End" }
		local errorLines = Verify.classifyConsole(lines, {
			blockBeginPatterns = { "Stack Begin" },
			blockEndPatterns = { "Stack End" },
		})
		assert.eq(errorLines, { lines[1], lines[2] })
	end)

	suite:case("keeps an unterminated block after an ignored line", function(assert)
		local lines = { "harmless notice refused by policy", "Stack Begin", "Frame 1" }
		local errorLines = Verify.classifyConsole(lines, {
			ignorePatterns = { "harmless notice" },
			blockBeginPatterns = { "Stack Begin" },
			blockEndPatterns = { "Stack End" },
		})
		assert.eq(errorLines, { lines[2] })
	end)

	suite:case("refuses one half of a block pattern pair", function(assert)
		assert.that(not pcall(Verify.classifyConsole, { "a" }, { blockBeginPatterns = { "Stack Begin" } }))
	end)

	suite:case("splits console text on either line ending before classifying", function(assert)
		local text = "loading\r\nattempt to index nil with 'Engine'\rall good\n"
		assert.eq(Verify.splitConsoleLines(text), { "loading", "attempt to index nil with 'Engine'", "all good" })
		assert.eq(Verify.classifyConsoleText(text), { "attempt to index nil with 'Engine'" })
	end)
end)
