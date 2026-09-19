--!strict

local test = require "@std/test"

local Consumer = require "../src/consumer"

local function codes(source: string, path: string): { string }
	local result: { string } = {}
	for _, finding in Consumer.scan(source, path) do
		table.insert(result, finding.code)
	end
	return result
end

test.suite("verify consumer lints", function(suite)
	suite:case("rejects ambient scheduling clocks and hosts in portable specifications", function(assert)
		assert.eq(codes("task.wait(); os.clock(); return game, workspace", "case.verify.luau"), {
			"VRF001",
			"VRF002",
			"VRF003",
			"VRF003",
		})
	end)

	suite:case("allows host access in an explicitly Roblox specification", function(assert)
		assert.eq(codes("return game, workspace", "case.roblox.verify.luau"), {})
	end)

	suite:case("rejects external mutation and unjustified native annotations in every specification", function(assert)
		assert.eq(codes("--!native\nservice:PublishAsync()", "case.roblox.verify.luau"), { "VRF005", "VRF004" })
	end)

	suite:case("ignores examples in comments and strings", function(assert)
		assert.eq(codes('-- task.wait()\nreturn "game:PublishAsync()"', "case.verify.luau"), {})
	end)

	suite:case("ignores examples inside long-bracket strings and long comments", function(assert)
		assert.eq(codes("local sample = [[game.Workspace]]\n", "case.verify.luau"), {})
		assert.eq(codes("local sample = [==[\ngame\nworkspace\n]==]\n", "case.verify.luau"), {})
		assert.eq(codes("--[[\ngame\ntask.wait()\n]]\nreturn nil\n", "case.verify.luau"), {})
	end)

	suite:case("ignores table fields and methods spelled like a host global", function(assert)
		assert.eq(codes("return raw.game.x, payload.workspace, handle:game()", "case.verify.luau"), {})
		assert.eq(codes("local fixture = load()\nreturn fixture.game, fixture . workspace\n", "case.verify.luau"), {})
	end)

	suite:case("still reports the global host after a field of the same name", function(assert)
		assert.eq(codes("return raw.game.x, game", "case.verify.luau"), { "VRF003" })
	end)

	suite:case("ignores calls to locally declared functions named like ambient globals", function(assert)
		assert.eq(codes("local function tick()\n\treturn 0\nend\nreturn tick()\n", "case.verify.luau"), {})
		assert.eq(codes("local tick = fixture\nreturn tick()\n", "case.verify.luau"), {})
		assert.eq(codes("local function run(wait)\n\treturn wait()\nend\n", "case.verify.luau"), {})
	end)

	suite:case("still reports the ambient clock and scheduler when nothing shadows them", function(assert)
		assert.eq(codes("return tick()", "case.verify.luau"), { "VRF002" })
		assert.eq(codes("wait(1)\nreturn nil\n", "case.verify.luau"), { "VRF001" })
	end)

	suite:case("rejects verification code in a production manifest", function(assert)
		local findings = Consumer.scanProductionPaths {
			"src/client/main.luau",
			"tests/combat.verify.luau",
			"packages/Verify/core/init.luau",
		}
		assert.eq(#findings, 2)
		assert.eq(findings[1].code, "VRF007")
		assert.eq(findings[2].code, "VRF006")
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
				contents[child] = body :: string
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

test.suite("verify consumer tree scan", function(suite)
	suite:case("scans every discovered specification and every discovered path", function(assert)
		local listDir, readFile = treeOf {
			["src/combat.verify.luau"] = "task.wait()\nreturn nil\n",
			["src/module.luau"] = "return game\n",
			["src/nested/other.roblox.verify.luau"] = "return game\n",
			["manifest/leaked.verify.luau"] = "return nil\n",
		}
		local result = Consumer.scanTree(".", { listDir = listDir, readFile = readFile })

		assert.eq(#result.findings, 1)
		assert.eq(result.findings[1].code, "VRF001")
		assert.eq(result.findings[1].path, "./src/combat.verify.luau")

		local productionCodes: { string } = {}
		for _, finding in result.productionFindings do
			table.insert(productionCodes, finding.code)
		end
		table.sort(productionCodes)
		assert.eq(productionCodes, { "VRF006", "VRF006", "VRF006" })
	end)

	suite:case("skips an exempted subtree entirely", function(assert)
		local listDir, readFile = treeOf {
			["vendor/skip.verify.luau"] = "task.wait()\nreturn nil\n",
			["src/combat.verify.luau"] = "return nil\n",
		}
		local result = Consumer.scanTree(".", {
			listDir = listDir,
			readFile = readFile,
			exempt = function(path: string): boolean
				return path == "./vendor"
			end,
		})
		assert.eq(#result.findings, 0)
		assert.eq(#result.productionFindings, 1)
		assert.eq(result.productionFindings[1].path, "./src/combat.verify.luau")
	end)

	suite:case("honors a custom specification test instead of the *.verify.luau default", function(assert)
		local listDir, readFile = treeOf {
			["specs/combat.verify.luau"] = "task.wait()\nreturn nil\n",
			["other/other.verify.luau"] = "task.wait()\nreturn nil\n",
		}
		local result = Consumer.scanTree(".", {
			listDir = listDir,
			readFile = readFile,
			isSpecification = function(path: string): boolean
				return string.match(path, "^%./specs/") ~= nil
			end,
		})
		assert.eq(#result.findings, 1)
		assert.eq(result.findings[1].code, "VRF001")
		assert.eq(result.findings[1].path, "./specs/combat.verify.luau")

		assert.eq(#result.productionFindings, 2)
	end)

	suite:case("refuses a call missing listDir or readFile", function(assert)
		assert.eq(
			pcall(function()
				(Consumer.scanTree :: any)(".", {})
			end),
			false
		)
	end)
end)
