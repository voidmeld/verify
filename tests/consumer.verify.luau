--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Consumer = require "../src/consumer"

local function codesWith(ruleset: Consumer.Ruleset, source: string, path: string): { string }
	local result: { string } = {}
	for _, finding in Consumer.scan(source, path, ruleset) do
		table.insert(result, finding.code)
	end
	return result
end

local function codes(source: string, path: string): { string }
	return codesWith(Consumer.roblox, source, path)
end

describe("verify consumer lints", function()
	it("rejects ambient scheduling clocks and hosts in portable specifications", function()
		expect((codes("task.wait(); os.clock(); return game, workspace", "case.verify.luau"))):toEqual {
			"VRF001",
			"VRF002",
			"VRF003",
			"VRF003",
		}
	end)

	it("the generic ruleset names no host global or mutation member", function()
		expect((codesWith(Consumer.generic, "return game, workspace", "case.verify.luau"))):toEqual {}
		expect((codesWith(Consumer.generic, "service:PublishAsync()", "case.verify.luau"))):toEqual {}
		expect((codesWith(Consumer.generic, "task.wait(); os.clock()", "case.verify.luau"))):toEqual {
			"VRF001",
			"VRF002",
		}
		expect((codesWith(Consumer.generic, "task.wait()", "case.roblox.verify.luau"))):toEqual { "VRF001" }
	end)

	it("refuses a scan without a ruleset", function()
		expect((pcall(function()
			Consumer.scan("return nil", "case.verify.luau", ({}) :: Consumer.Ruleset)
		end))):toEqual(false)
	end)

	it("allows host access in an explicitly Roblox specification", function()
		expect((codes("return game, workspace", "case.roblox.verify.luau"))):toEqual {}
	end)

	it("rejects external mutation and unjustified native annotations in every specification", function()
		expect((codes("--!native\nservice:PublishAsync()", "case.roblox.verify.luau"))):toEqual { "VRF005", "VRF004" }
	end)

	it("ignores examples in comments and strings", function()
		expect((codes('-- task.wait()\nreturn "game:PublishAsync()"', "case.verify.luau"))):toEqual {}
	end)

	it("ignores examples inside long-bracket strings and long comments", function()
		expect((codes("local sample = [[game.Workspace]]\n", "case.verify.luau"))):toEqual {}
		expect((codes("local sample = [==[\ngame\nworkspace\n]==]\n", "case.verify.luau"))):toEqual {}
		expect((codes("--[[\ngame\ntask.wait()\n]]\nreturn nil\n", "case.verify.luau"))):toEqual {}
	end)

	it("ignores table fields and methods spelled like a host global", function()
		expect((codes("return raw.game.x, payload.workspace, handle:game()", "case.verify.luau"))):toEqual {}
		expect((codes("local fixture = load()\nreturn fixture.game, fixture . workspace\n", "case.verify.luau"))):toEqual {}
	end)

	it("still reports the global host after a field of the same name", function()
		expect((codes("return raw.game.x, game", "case.verify.luau"))):toEqual { "VRF003" }
	end)

	it("ignores calls to locally declared functions named like ambient globals", function()
		expect((codes("local function tick()\n\treturn 0\nend\nreturn tick()\n", "case.verify.luau"))):toEqual {}
		expect((codes("local tick = fixture\nreturn tick()\n", "case.verify.luau"))):toEqual {}
		expect((codes("local function run(wait)\n\treturn wait()\nend\n", "case.verify.luau"))):toEqual {}
	end)

	it("still reports the ambient clock and scheduler when nothing shadows them", function()
		expect((codes("return tick()", "case.verify.luau"))):toEqual { "VRF002" }
		expect((codes("wait(1)\nreturn nil\n", "case.verify.luau"))):toEqual { "VRF001" }
	end)

	it("rejects verification code in a production manifest", function()
		local findings = Consumer.scanProductionPaths {
			"src/client/main.luau",
			"tests/alpha.verify.luau",
			"packages/Verify/core/init.luau",
		}
		expect(#findings):toEqual(2)
		expect(findings[1].code):toEqual "VRF007"
		expect(findings[2].code):toEqual "VRF006"
	end)
end)

local function treeOf(files: { [string]: string? }): (Consumer.ListDir, Consumer.ReadFile)
	local children: { [string]: { Consumer.DirEntry } } = {}
	local contents: { [string]: string } = {}

	local function ensure(dir: string)
		if children[dir] == nil then
			children[dir] = {}
		end
	end

	for path, body in files do
		local segments: { string } = {}
		for segment in string.gmatch(path, "[^/]+") do
			table.insert(segments, segment)
		end
		local prefix = "."
		ensure(prefix)
		for index, segment in segments do
			local child = prefix .. "/" .. segment
			local isFile = index == #segments
			ensure(prefix)
			local already = false
			for _, entry in children[prefix] do
				if entry.name == segment then
					already = true
				end
			end
			if not already then
				table.insert(children[prefix], { name = segment, type = if isFile then "file" else "dir" })
			end
			if isFile then
				contents[child] = assert(body)
			else
				ensure(child)
			end
			prefix = child
		end
	end

	local function listDir(path: string): { Consumer.DirEntry }
		return children[path] or {}
	end
	local function readFile(path: string): string
		return contents[path] or error("no such fixture file: " .. path, 2)
	end
	return listDir, readFile
end

describe("verify consumer tree scan", function()
	it("scans every discovered specification and every discovered path", function()
		local listDir, readFile = treeOf {
			["src/alpha.verify.luau"] = "task.wait()\nreturn nil\n",
			["src/module.luau"] = "return game\n",
			["src/nested/other.roblox.verify.luau"] = "return game\n",
			["manifest/leaked.verify.luau"] = "return nil\n",
		}
		local result = Consumer.scanTree(".", { ruleset = Consumer.roblox, listDir = listDir, readFile = readFile })

		expect(#result.findings):toEqual(1)
		expect(result.findings[1].code):toEqual "VRF001"
		expect(result.findings[1].path):toEqual "./src/alpha.verify.luau"

		local productionCodes: { string } = {}
		for _, finding in result.productionFindings do
			table.insert(productionCodes, finding.code)
		end
		table.sort(productionCodes)
		expect(productionCodes):toEqual { "VRF006", "VRF006", "VRF006" }
	end)

	it("skips an exempted subtree entirely", function()
		local listDir, readFile = treeOf {
			["vendor/skip.verify.luau"] = "task.wait()\nreturn nil\n",
			["src/alpha.verify.luau"] = "return nil\n",
		}
		local result = Consumer.scanTree(".", {
			ruleset = Consumer.roblox,
			listDir = listDir,
			readFile = readFile,
			exempt = function(path: string): boolean
				return path == "./vendor"
			end,
		})
		expect(#result.findings):toEqual(0)
		expect(#result.productionFindings):toEqual(1)
		expect(result.productionFindings[1].path):toEqual "./src/alpha.verify.luau"
	end)

	it("honors a custom specification test instead of the *.verify.luau default", function()
		local listDir, readFile = treeOf {
			["specs/alpha.verify.luau"] = "task.wait()\nreturn nil\n",
			["other/other.verify.luau"] = "task.wait()\nreturn nil\n",
		}
		local result = Consumer.scanTree(".", {
			ruleset = Consumer.roblox,
			listDir = listDir,
			readFile = readFile,
			isSpecification = function(path: string): boolean
				return string.match(path, "^%./specs/") ~= nil
			end,
		})
		expect(#result.findings):toEqual(1)
		expect(result.findings[1].code):toEqual "VRF001"
		expect(result.findings[1].path):toEqual "./specs/alpha.verify.luau"

		expect(#result.productionFindings):toEqual(2)
	end)

	it("refuses a call missing listDir or readFile", function()
		expect((pcall(function()
			Consumer.scanTree(".", ({}) :: Consumer.TreeOptions)
		end))):toEqual(false)
	end)
end)

return nil
