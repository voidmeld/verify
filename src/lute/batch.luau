--!strict

local json = require "@std/json"

local Batch = require "../runtime/batch"

local bound = Batch.create {
	encode = function(value: unknown): string
		return json.serialize(value :: json.Value)
	end,
	decode = function(encoded: string): unknown
		return json.deserialize(encoded)
	end,
}

return {
	WIRE_VERSION = Batch.WIRE_VERSION,
	encode = bound.encode,
	decode = bound.decode,
}
