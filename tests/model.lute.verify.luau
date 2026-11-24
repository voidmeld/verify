--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Lute = require "../src/lute"

local MODEL = table.concat({
	'<?xml version="1.0"?>\r\n<roblox version="4">\r\n',
	'<!-- built -->\r\n<Item class="Folder" referent="0"><Properties><string name="Name">Lib</string></Properties>\r\n',
	'<Item class="ModuleScript"><Properties><string name="Name">a &amp; b</string>',
	'<ProtectedString name="Source"><![CDATA[return "<x>"\r\n]]></ProtectedString>',
	'<bool name="Archivable">true</bool></Properties></Item>\r\n',
	'<Item class="Configuration"><Properties/></Item>\r\n',
	'<Item class="StringValue"><Properties><string name="Name"></string></Properties></Item>\r\n',
	"</Item>\r\n</roblox>\r\n",
}, "")

local function failure(text: string): string
	local ok, problem: unknown = pcall(Lute.model.read, text)
	assert(not ok, "the read must fail")
	return tostring(problem)
end

describe("model files", function()
	it("reads instances with names, paths and typed property values", function()
		local roots = Lute.model.read(MODEL)
		expect(#roots):toBe(1)
		local folder = roots[1]
		expect(folder.className):toBe "Folder"
		expect(folder.path):toBe "Lib"
		expect(#folder.children):toBe(3)
		local module = folder.children[1]
		expect(module.name):toBe "a & b"
		expect(module.path):toBe "Lib/a & b"
		expect(module.properties.Source):toEqual { type = "ProtectedString", value = 'return "<x>"\n' }
		expect(module.properties.Archivable):toEqual { type = "bool", value = "true" }
		expect(folder.children[2].name):toBe "Configuration"
		expect(folder.children[3].path):toBe "Lib/StringValue"
	end)

	it("walks the tree in document order and finds an instance by path", function()
		local roots = Lute.model.read(MODEL)
		local paths: { string } = {}
		for _, item in Lute.model.descendants(roots) do
			table.insert(paths, item.path)
		end
		expect(paths):toEqual { "Lib", "Lib/a & b", "Lib/Configuration", "Lib/StringValue" }
		expect((assert(Lute.model.find(roots, "Lib/Configuration"))).className):toBe "Configuration"
		expect(Lute.model.find(roots, "Lib/absent")):toBe(nil)
	end)

	it("refuses a document that is not a well-formed Roblox file", function()
		expect(failure "<model></model>"):toContain "not a Roblox XML model or place"
		expect(failure '<roblox><Item class="Folder"></roblox>'):toContain "mismatched closing tag"
		expect(failure "<roblox><Item>"):toContain "unclosed element"
		expect(failure "<roblox><![CDATA[x</roblox>"):toContain "unterminated CDATA section"
		expect(failure "plain text"):toContain "no root element"
	end)
end)

return nil
