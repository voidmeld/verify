--!strict

local json = require "@std/json"

local Wire = require "../runtime/wire"

local bound = Wire.create {
	encode = function(value: unknown): string
		return json.serialize(value :: json.Value)
	end,
	decode = function(encoded: string): unknown
		return json.deserialize(encoded)
	end,
}

return {
	encode = bound.encode,
	parse = bound.parse,
	decode = bound.decode,
	normalize = Wire.normalize,
	segmentReport = bound.segmentReport,
	reassembleReport = bound.reassembleReport,
}
