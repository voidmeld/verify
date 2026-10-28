--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local temporary = require "./temporary"

local fs = require "@std/fs"
local Core = require "../src/core"
local Place = require "../src/lute/place"
local Model = require "../src/lute/model"

local function directory(context: Core.Context): string
	local root = temporary(context, "verify-place-tests")
	return root
end
describe("native place bundler", function()
	it("mounts literal import closures and escapes script source", function(_, caseContext)
		local root = directory(caseContext)
		fs.createDirectory(root .. "/library")
		fs.writeStringToFile(root .. "/library/init.luau", "local child = require '@self/child'\nreturn child")
		fs.writeStringToFile(root .. "/library/child.luau", "return '<widget & value>'")
		fs.writeStringToFile(
			root .. "/case.luau",
			'local library=require("./library")\nlocal text="require \\"./missing\\""\nreturn library'
		)
		Place.build {
			output = root .. "/result.rbxlx",
			roots = { root .. "/library" },
			modules = { root .. "/case.luau" },
			clientSource = "print('<client>')",
			serverSource = "print('<server>')",
		}
		local output = fs.readFileToString(root .. "/result.rbxlx")
		expect(output:find("VerifyModules", 1, true) ~= nil):toBe(true)
		expect(output:find('<token name="Technology">4</token>', 1, true) ~= nil):toBe(true)
		expect(output:find("&lt;widget &amp; value&gt;", 1, true) ~= nil):toBe(true)
		expect(output:find("VerifyClient", 1, true) ~= nil):toBe(true)
		expect(output:find("VerifyServer", 1, true) ~= nil):toBe(true)
		expect(output:find("&lt;client&gt;", 1, true) ~= nil):toBe(true)
		expect(output:find("require(&quot;", 1, true) == nil):toBe(true)
		expect(output:find("./missing", 1, true) ~= nil):toBe(true)
	end)
	it("bundles a standalone module closure without world or bootstrap instances", function(_, caseContext)
		local root = directory(caseContext)
		fs.writeStringToFile(root .. "/child.luau", "return '<child & value>'")
		fs.writeStringToFile(root .. "/entry.luau", 'return require "./child"')
		local bundled =
			Model.read(Place.bundle { roots = {}, modules = { root .. "/entry.luau" }, rootName = "Mounted" })
		expect(#bundled):toBe(1)
		expect(bundled[1].name):toBe "Mounted"
		local sources: { [string]: string } = {}
		for _, item in Model.descendants(bundled) do
			if item.className == "ModuleScript" then
				sources[item.name] = item.properties.Source.value
			else
				expect(item.className):toBe "Folder"
			end
		end
		expect(sources.child):toBe "return '<child & value>'"
		expect(sources.entry):toBe("return require(" .. Place.moduleExpression(root .. "/child.luau", "Mounted") .. ")")
	end)
	it("mounts verbatim modules at their paths without rewriting their imports", function(_, caseContext)
		local root = directory(caseContext)
		fs.writeStringToFile(root .. "/entry.luau", 'return require "./child"')
		fs.writeStringToFile(root .. "/child.luau", "return 1")
		local verbatim = {
			["packages/library"] = "return require(script.Value)",
			["packages/library/Value"] = 'return require("./Other")',
			["packages/Other"] = "return 2",
		}
		local bundled = Model.read(Place.bundle {
			roots = {},
			modules = { root .. "/entry.luau" },
			verbatim = verbatim,
			rootName = "Mounted",
		})
		local sources: { [string]: string } = {}
		local parents: { [string]: string } = {}
		local function walk(item: Model.Instance, parent: string)
			parents[item.name] = parent
			if item.className == "ModuleScript" then
				sources[item.name] = item.properties.Source.value
			end
			for _, child in item.children do
				walk(child, item.name)
			end
		end
		walk(bundled[1], "")
		expect(sources.library):toBe "return require(script.Value)"
		expect(sources.Value):toBe 'return require("./Other")'
		expect(sources.Other):toBe "return 2"
		expect(parents.Value):toBe "library"
		expect(parents.library):toBe "packages"
		expect(parents.packages):toBe "Mounted"
		expect(function()
			Place.bundle { roots = {}, verbatim = { [""] = "return 1" } }
		end):toThrow "verbatim module needs a path"
	end)

	it("rejects missing external and dynamic imports and ambiguous module mounts", function(_, caseContext)
		local root = directory(caseContext)
		local source = root .. "/case.luau"
		for _, contents in { 'return require "./missing"', 'return require "@std/fs"', "return require(variable)" } do
			fs.writeStringToFile(source, contents)
			expect(pcall(function()
				Place.build { output = root .. "/result.rbxlx", roots = {}, modules = { source } }
			end)):toBe(false)
			expect(fs.exists(root .. "/result.rbxlx")):toBe(false)
		end
		fs.writeStringToFile(source, "return true")
		fs.createDirectory(root .. "/case")
		fs.writeStringToFile(root .. "/case/init.luau", "return false")
		expect(pcall(function()
			Place.build { output = root .. "/result.rbxlx", roots = { root .. "/case" }, modules = { source } }
		end)):toBe(false)
	end)
	it("does not rewrite comments or string examples and normalizes module expressions", function(_, caseContext)
		local root = directory(caseContext)
		local source = root .. "/example.luau"
		fs.writeStringToFile(
			source,
			'-- require "./absent"\nlocal a=[=[require("@bad/import")]=]\nlocal b="require \\"bad\\""\nreturn a..b'
		)
		Place.build { output = root .. "/result.rbxlx", roots = {}, modules = { source } }
		local text = fs.readFileToString(root .. "/result.rbxlx")
		expect(text:find("@bad/import", 1, true) ~= nil):toBe(true)
		expect(Place.moduleExpression "src/./core/../core/init.luau"):toBe 'game:GetService("ReplicatedStorage"):WaitForChild("VerifyModules"):WaitForChild("src"):WaitForChild("core")'
		expect(Place.moduleExpression("runtime/children.luau"):find(':WaitForChild("children")', 1, true) ~= nil):toBe(
			true
		)
		expect(pcall(function()
			Place.moduleExpression "../escape.luau"
		end)):toBe(false)
	end)
	it("resolves relative imports as the runtime does for ordinary files and init files", function(_, caseContext)
		local root = directory(caseContext)
		fs.createDirectory(root .. "/src")
		fs.createDirectory(root .. "/src/core")
		fs.createDirectory(root .. "/src/roblox")
		fs.createDirectory(root .. "/src/plain")
		fs.writeStringToFile(root .. "/src/core/init.luau", "return 'core'")
		fs.writeStringToFile(root .. "/src/roblox/x.luau", "return 'child'")
		fs.writeStringToFile(root .. "/src/plain/leaf.luau", "return 'leaf'")
		fs.writeStringToFile(
			root .. "/src/roblox/init.luau",
			'local a = require "./core"\nlocal b = require "@self/x"\nlocal c = require "../src/plain/leaf"\nreturn { a, b, c }'
		)
		fs.writeStringToFile(
			root .. "/src/plain/sibling.luau",
			'local a = require "./leaf"\nlocal b = require "../core"\nlocal c = require "../roblox"\nreturn { a, b, c }'
		)
		Place.build {
			output = root .. "/result.rbxlx",
			roots = { root .. "/src/roblox", root .. "/src/plain" },
			modules = {},
		}
		local output = fs.readFileToString(root .. "/result.rbxlx")
		local function expression(path: string): string
			return Place.moduleExpression(path):gsub("&", "&amp;"):gsub('"', "&quot;")
		end
		local rooted = root:gsub("^/", "")
		expect(output:find(expression(rooted .. "/src/core"), 1, true) ~= nil):toBe(true)
		expect(output:find(expression(rooted .. "/src/roblox/x"), 1, true) ~= nil):toBe(true)
		expect(output:find(expression(rooted .. "/src/plain/leaf"), 1, true) ~= nil):toBe(true)
		expect(output:find(expression(rooted .. "/src/roblox"), 1, true) ~= nil):toBe(true)
	end)
	it("rejects an init import that only resolves from the init directory", function(_, caseContext)
		local root = directory(caseContext)
		fs.createDirectory(root .. "/lib")
		fs.createDirectory(root .. "/lib/inner")
		fs.writeStringToFile(root .. "/lib/inner/init.luau", 'return require "./only"')
		fs.writeStringToFile(root .. "/lib/inner/only.luau", "return 1")
		expect(pcall(function()
			Place.build { output = root .. "/result.rbxlx", roots = { root .. "/lib/inner" }, modules = {} }
		end)):toBe(false)
		expect(fs.exists(root .. "/result.rbxlx")):toBe(false)
		fs.writeStringToFile(root .. "/lib/inner/init.luau", 'return require "@self/only"')
		Place.build { output = root .. "/result.rbxlx", roots = { root .. "/lib/inner" }, modules = {} }
		expect(fs.exists(root .. "/result.rbxlx")):toBe(true)
	end)
	it("merges the mounted tree and entry scripts into a copy of a base place", function(_, caseContext)
		local root = directory(caseContext)
		fs.createDirectory(root .. "/lib")
		fs.writeStringToFile(root .. "/lib/init.luau", "local child = require '@self/child'\nreturn child")
		fs.writeStringToFile(root .. "/lib/child.luau", "return 1")
		local base = '<roblox version="4"><Item class="ReplicatedStorage"><Item class="Folder"><Properties><string name="Name">Keep</string></Properties></Item></Item>'
			.. '<Item class="Workspace"><Item class="Part"><Properties><string name="Name">Base &lt;part&gt;</string></Properties></Item></Item>'
			.. '<Item class="ServerScriptService"><Item class="Script"><Properties><string name="Name">Other</string><ProtectedString name="Source"><![CDATA[print("</Item>")]]></ProtectedString></Properties></Item></Item></roblox>'
		fs.writeStringToFile(root .. "/base.rbxlx", base)
		Place.build {
			output = root .. "/merged.rbxlx",
			basePlace = root .. "/base.rbxlx",
			roots = { root .. "/lib" },
			modules = {},
			clientSource = "print('c')",
			serverSource = "print('s')",
			rootName = "Mounted",
		}
		local merged = fs.readFileToString(root .. "/merged.rbxlx")
		expect(merged:find("Base &lt;part&gt;", 1, true) ~= nil):toBe(true)
		expect(merged:find('<string name="Name">Keep</string>', 1, true) ~= nil):toBe(true)
		expect(merged:find('<![CDATA[print("</Item>")]]>', 1, true) ~= nil):toBe(true)
		expect(merged:find('<string name="Name">Mounted</string>', 1, true) ~= nil):toBe(true)
		expect(merged:find('<string name="Name">Other</string>', 1, true) ~= nil):toBe(true)
		expect(merged:find('<string name="Name">Floor</string>', 1, true) == nil):toBe(true)
		expect(merged:find("VerifyClient", 1, true) ~= nil):toBe(true)
		expect(merged:find("VerifyServer", 1, true) ~= nil):toBe(true)
		expect(select(2, merged:gsub('class="ReplicatedStorage"', ""))):toBe(1)
		expect(select(2, merged:gsub('class="ServerScriptService"', ""))):toBe(1)
		expect(select(2, merged:gsub('class="StarterPlayerScripts"', ""))):toBe(1)
		expect(
			merged:find("game:GetService(&quot;ReplicatedStorage&quot;):WaitForChild(&quot;Mounted&quot;)", 1, true)
				~= nil
		):toBe(true)
		expect(base):toBe(fs.readFileToString(root .. "/base.rbxlx"))
	end)
	it("refuses a base that holds the module root name, a binary base and a clashing script", function(_, caseContext)
		local root = directory(caseContext)
		fs.writeStringToFile(root .. "/m.luau", "return 1")
		local function build(base: string, extra: { [string]: string }?)
			fs.writeStringToFile(root .. "/base.rbxlx", base)
			local options: Place.Options = {
				output = root .. "/out.rbxlx",
				basePlace = root .. "/base.rbxlx",
				roots = {},
				modules = { root .. "/m.luau" },
				serverSource = if extra ~= nil then extra.server else nil,
			}
			return pcall(function(): string?
				Place.build(options)
				return nil
			end)
		end
		local taken =
			'<roblox version="4"><Item class="ReplicatedStorage"><Item class="Folder"><Properties><string name="Name">VerifyModules</string></Properties></Item></Item></roblox>'
		local ok, message = build(taken)
		expect(ok):toBe(false)
		expect(tostring(message)):toContain "already contains an instance named VerifyModules"
		local binaryOk, binary = build "<roblox!\137\255\13\10"
		expect(binaryOk):toBe(false)
		expect(tostring(binary)):toContain "only an XML place"
		local clash =
			'<roblox version="4"><Item class="ServerScriptService"><Item class="Script"><Properties><string name="Name">VerifyServer</string></Properties></Item></Item></roblox>'
		local clashOk, clashed = build(clash, { server = "print(1)" })
		expect(clashOk):toBe(false)
		expect(tostring(clashed)):toContain "VerifyServer"
		expect(fs.exists(root .. "/out.rbxlx")):toBe(false)
		local bare = build '<roblox version="4"></roblox>'
		expect(bare):toBe(true)
		expect(fs.readFileToString(root .. "/out.rbxlx"):find('class="ReplicatedStorage"', 1, true) ~= nil):toBe(true)
	end)
	it("bundles the real portable framework dependency graph", function(_, caseContext)
		local root = directory(caseContext)
		Place.build {
			output = root .. "/framework.rbxlx",
			roots = { "src/core", "src/roblox" },
			modules = { "examples/instance-case.luau" },
			rootName = "VerifySemanticFixture",
		}
		expect(#fs.readFileToString(root .. "/framework.rbxlx") > 100000):toBe(true)
	end)
end)

return nil
