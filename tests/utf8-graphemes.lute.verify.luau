--!strict

local Test = require "./harness"
local it, expect = Test.it, Test.expect
local Utf8Library = require "../src/roblox/utf8-library"

local function spans(text: string): { string }
	local result: { string } = {}
	for first, last in Utf8Library.graphemes(text) do
		table.insert(result, string.sub(text, first, last))
	end
	return result
end

it("splits ASCII and multibyte text one cluster per character", function()
	expect(#spans "abc"):toBe(3)
	expect(#spans ""):toBe(0)
	expect(#spans "h\u{e9}llo"):toBe(5)
end)

it("keeps combining marks and variation selectors with their base", function()
	expect(#spans "e\u{301}x"):toBe(2)
	expect(#spans "\u{2764}\u{FE0F}!"):toBe(2)
	expect(#spans "\u{1F44D}\u{1F3FD}"):toBe(1)
end)

it("keeps zero-width joiner sequences together", function()
	expect(#spans "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"):toBe(1)
end)

it("reports byte positions and the place runtime exposes the library", function()
	local first, last = Utf8Library.graphemes "\u{e9}a"()
	expect(first):toBe(1)
	expect(last):toBe(2)
	expect(type(Utf8Library.create().graphemes)):toBe "function"
	expect(type(Utf8Library.create().len)):toBe "function"
end)

return nil
