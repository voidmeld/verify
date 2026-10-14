--!strict

local Lute = require "../src/lute"
local Verify = require "../src/core"

local MODEL = table.concat({
	'<?xml version="1.0"?>\r\n<roblox version="4">\r\n',
	'<!-- built -->\r\n<Item class="Folder" referent="0"><Properties><string name="Name">Lib</string></Properties>\r\n',
	'<Item class="ModuleScript"><Properties><string name="Name">a &amp; b</string>',
	'<ProtectedString name="Source"><![CDATA[return "<x>"\r\n]]></ProtectedString>',
	'<bool name="Archivable">true</bool></Properties></Item>\r\n',
	'<Item class="Configuration"><Properties/></Item>\r\n',
	"</Item>\r\n</roblox>\r\n",
}, "")

local function failure(text: string): string
	local ok, problem: unknown = pcall(Lute.model.read, text)
	assert(not ok, "the read must fail")
	return tostring(problem)
end

return function(suite: Verify.Harness)
	suite:suite("model files", function()
		suite:case("reads instances with names, paths and typed property values", function(check)
			local roots = Lute.model.read(MODEL)
			check:expect(#roots):toBe(1)
			local folder = roots[1]
			check:expect(folder.className):toBe "Folder"
			check:expect(folder.path):toBe "Lib"
			check:expect(#folder.children):toBe(2)
			local module = folder.children[1]
			check:expect(module.name):toBe "a & b"
			check:expect(module.path):toBe "Lib/a & b"
			check:expect(module.properties.Source):toEqual { type = "ProtectedString", value = 'return "<x>"\n' }
			check:expect(module.properties.Archivable):toEqual { type = "bool", value = "true" }
			check:expect(folder.children[2].name):toBe "Configuration"
		end)

		suite:case("walks the tree in document order and finds an instance by path", function(check)
			local roots = Lute.model.read(MODEL)
			local paths: { string } = {}
			for _, item in Lute.model.descendants(roots) do
				table.insert(paths, item.path)
			end
			check:expect(paths):toEqual { "Lib", "Lib/a & b", "Lib/Configuration" }
			check
				:expect((Lute.model.find(roots, "Lib/Configuration") :: Lute.ModelInstance).className)
				:toBe "Configuration"
			check:expect(Lute.model.find(roots, "Lib/absent")):toBe(nil)
		end)

		suite:case("refuses a document that is not a well-formed Roblox file", function(check)
			check:expect(failure "<model></model>"):toContain "not a Roblox XML model or place"
			check:expect(failure '<roblox><Item class="Folder"></roblox>'):toContain "mismatched closing tag"
			check:expect(failure "<roblox><Item>"):toContain "unclosed element"
			check:expect(failure "<roblox><![CDATA[x</roblox>"):toContain "unterminated CDATA section"
			check:expect(failure "plain text"):toContain "no root element"
		end)
	end)
end
