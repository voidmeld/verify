--!strict

local Verify = require "../core"
local Binding = require "./binding"

type Report = Verify.Report
type Segment = Verify.Segment

export type Wire = {
	encode: (value: unknown) -> string,
	parse: (encoded: string) -> unknown,
	decode: (encoded: string) -> Report,
	normalize: (value: unknown) -> unknown,
	segmentReport: (report: Report, maxBytes: number) -> { Segment },
	reassembleReport: (segments: { Segment }) -> (Report?, string?),
}

local function normalize(value: unknown): unknown
	if type(value) ~= "table" then
		return value
	end
	local result: { [unknown]: unknown } = {}
	for key, item in value :: { [unknown]: unknown } do
		if type(key) == "string" or type(key) == "number" then
			result[key] = normalize(item)
		end
	end
	return result
end

local function create(json: Binding.Json): Wire
	local function encode(value: unknown): string
		return json.encode(value)
	end

	local function parse(encoded: string): unknown
		return normalize(json.decode(encoded))
	end

	local function decode(encoded: string): Report
		return Verify.decode(parse(encoded))
	end

	local function segmentReport(report: Report, maxBytes: number): { Segment }
		return Verify.segment(encode(report), maxBytes)
	end

	local function reassembleReport(segments: { Segment }): (Report?, string?)
		local bytes, reason = Verify.reassembleSegments(segments)
		if bytes == nil then
			return nil, reason
		end
		local decoded, value: unknown = pcall(decode, bytes :: string)
		if not decoded then
			return nil, "reassembled bytes did not decode to a report: " .. tostring(value)
		end
		return value :: Report, nil
	end

	return {
		encode = encode,
		parse = parse,
		decode = decode,
		normalize = normalize,
		segmentReport = segmentReport,
		reassembleReport = reassembleReport,
	}
end

return {
	create = create,
	normalize = normalize,
}
