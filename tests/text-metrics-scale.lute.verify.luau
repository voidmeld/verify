--!strict

local Test = require "./harness"
local it, expect = Test.it, Test.expect
local fs = require "@std/fs"
local Wire = require "../src/lute/wire"
local Metrics = require "../src/roblox/text-metrics"

type Sample = {
	pixelScale: number,
	tokens: { string },
	pairs: { { number } },
	rows: { Metrics.Row & { size: number, samples: { { text: string, width: number } } } },
}

local sample = Wire.parse(fs.readFileToString "tests/fixtures/source-sans-pro-bold.json") :: Sample

it("SourceSansPro Bold preserves native raster scaling and float32 widths at captured sizes", function()
	for _, row in sample.rows do
		local model = Metrics.create {
			tokens = sample.tokens,
			pairs = sample.pairs,
			sizes = table.create(100, row),
			pixelScale = sample.pixelScale,
		}
		for _, entry in row.samples do
			expect(model.width(entry.text, row.size)):toBe(entry.width)
		end
		expect(model.height(row.size)):toBe(row.height)
	end
end)

it("scaled text compares wrap and truncation limits in returned units", function()
	local row = { advances = { 3, 3, 3 }, adjustments = {}, height = sample.pixelScale }
	local model = Metrics.create {
		tokens = { "A", " ", utf8.char(0x2026) },
		pairs = {},
		sizes = table.create(100, row),
		pixelScale = sample.pixelScale,
	}
	local width, lines = model.wrap("A A", 1, 3)
	expect(width):toBe(2)
	expect(lines):toBe(2)
	expect(model.truncate("AA AA AA", 1, 8, 1, "AtEnd", false)):toBe(6)
	expect(model.truncate("AA AA AA", 1, 1, 1, "AtEnd", false)):toBe(0)
end)

return nil
