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

it("Guru period-prefixed ligatures preserve native kerning and text boundaries", function()
	local face = Wire.parse(fs.readFileToString "src/lute/fixtures/text/Guru-Regular-Normal.json") :: Metrics.Face
	local model = Metrics.create(face)
	for _, entry in
		{
			{ text = "W.n", width = 110 },
			{ text = "W.m", width = 130.6666717529297 },
			{ text = "W.N", width = 120 },
			{ text = ".n", width = 68 },
			{ text = " .n", width = 88.66667175292969 },
			{ text = "W..n", width = 120.66667175292969 },
			{ text = "W.nW", width = 178.6666717529297 },
			{ text = "W.n W.n ", width = 261.3333435058594 },
		}
	do
		expect(model.width(entry.text, 100)):toBe(entry.width)
	end
end)

return nil
