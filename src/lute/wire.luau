--!strict

local json = require "@std/json"

local Verify = require "../core"

type Report = Verify.Report

local function encode(report: Report): string
	return json.serialize(report)
end

local function normalize(value: unknown): unknown
	if type(value) ~= "table" then
		return value
	end
	local result: { [any]: any } = {}
	for key, item in value :: { [any]: any } do
		if type(key) == "string" or type(key) == "number" then
			result[key] = normalize(item)
		end
	end
	return result
end

local function parse(encoded: string): unknown
	return normalize(json.deserialize(encoded))
end

local function decode(encoded: string): Report
	return Verify.decode(parse(encoded))
end

type Segment = Verify.Segment

local function segmentReport(report: Report, maxBytes: number): { Segment }
	return Verify.segment(encode(report), maxBytes)
end

local function reassembleReport(segments: { Segment }): (Report?, string?)
	local bytes, reason = Verify.reassembleSegments(segments)
	if bytes == nil then
		return nil, reason
	end
	local decoded, value: any = pcall(decode, bytes :: string)
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
