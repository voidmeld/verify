--!strict

local Test = require "./harness"
local it, expect = Test.it, Test.expect
local fs = require "@std/fs"
local Wire = require "../src/lute/wire"
local NativeMetrics = require "../src/lute/text-metrics"
local Shape = require "../src/core/shape"
local Metrics = require "../src/roblox/text-metrics"

type Sample = {
	pixelScale: number,
	tokens: { string },
	pairs: { { number } },
	rows: { Metrics.Row & { size: number, samples: { { text: string, width: number } } } },
}

local function numbers(value: unknown): { number }
	assert(type(value) == "table")
	local result: { number } = {}
	for _, item in value do
		assert(type(item) == "number")
		table.insert(result, item)
	end
	return result
end
local function decodeSample(value: unknown): Sample
	local root = Shape.record(value, "sample")
	local scale = root.pixelScale
	assert(type(scale) == "number")
	local pairs: { { number } } = {}
	local rawPairs, rawRows = root.pairs, root.rows
	assert(type(rawPairs) == "table" and type(rawRows) == "table")
	for _, pair in rawPairs do
		table.insert(pairs, numbers(pair))
	end
	local rows: { Metrics.Row & { size: number, samples: { { text: string, width: number } } } } = {}
	for _, raw in rawRows do
		local row = Shape.record(raw, "row")
		local size, height, rawSamples = row.size, row.height, row.samples
		assert(type(size) == "number" and type(height) == "number" and type(rawSamples) == "table")
		local samples: { { text: string, width: number } } = {}
		for _, rawEntry in rawSamples do
			local entry = Shape.record(rawEntry, "entry")
			local text, width = entry.text, entry.width
			assert(type(text) == "string" and type(width) == "number")
			table.insert(samples, { text = text, width = width })
		end
		table.insert(rows, {
			advances = numbers(row.advances),
			adjustments = numbers(row.adjustments),
			size = size,
			height = height,
			samples = samples,
		})
	end
	return { pixelScale = scale, tokens = Shape.copyStrings(root.tokens, "tokens"), pairs = pairs, rows = rows }
end
local sample = decodeSample(Wire.parse(fs.readFileToString "tests/fixtures/source-sans-pro-bold.json"))

it("SourceSansPro Bold preserves native raster scaling and float32 widths at captured sizes", function()
	for _, row in sample.rows do
		local metrics: Metrics.Row = { advances = row.advances, adjustments = row.adjustments, height = row.height }
		local model = Metrics.create {
			tokens = sample.tokens,
			pairs = sample.pairs,
			sizes = table.create(100, metrics),
			pixelScale = sample.pixelScale,
		}
		for _, entry in row.samples do
			expect(model.width(entry.text, row.size)):toBe(entry.width)
		end
		expect(model.height(row.size)):toBe(row.height)
	end
end)

it("scaled text compares wrap and truncation limits in returned units", function()
	local row: Metrics.Row = { advances = { 3, 3, 3 }, adjustments = {}, height = sample.pixelScale }
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
	local face = NativeMetrics.decode(fs.readFileToString "src/lute/fixtures/text/Guru-Regular-Normal.json")
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

it("BuilderSans arrow ligatures retain native spacing around punctuation", function()
	local face = NativeMetrics.decode(fs.readFileToString "src/lute/fixtures/text/BuilderSans-Regular-Normal.json")
	local model = Metrics.create(face)
	for _, row in
		{
			{ text = ",<-", size = 14, width = 11.333333969116211 },
			{ text = "->7", size = 19, width = 18 },
			{ text = "-^/", size = 23, width = 18 },
			{ text = "->>", size = 24, width = 24 },
			{ text = "—.R-", size = 14, width = 22 },
		}
	do
		expect(model.width(row.text, row.size)):toBe(row.width)
	end
end)

it("truncation rounds the combined raster width once at a fractional boundary", function()
	local row: Metrics.Row = { advances = { 4, 2 }, adjustments = {} }
	local model = Metrics.create {
		tokens = { "A", "…" },
		pairs = {},
		sizes = table.create(100, row),
		pixelScale = 2 / 3,
	}
	expect(model.truncate("AAAA", 1, 4, 1, "SplitWord", false)):toBe(4)
	expect(model.truncate("AAAA", 1, 3.9, 1, "SplitWord", false)):toBe(model.width("…", 1))
end)

return nil
