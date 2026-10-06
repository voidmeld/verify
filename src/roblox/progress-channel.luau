--!strict

local Core = require "../core"

local TAG = "VERIFY_PROGRESS"
local FRAME_LIMIT = 100000

export type Collected = {
	events: { Core.ProgressEvent },
	rejected: number,
	foreign: number,
	first: string?,
}

local function toHex(text: string): string
	return (
		string.gsub(text, ".", function(character: string): string
			return string.format("%02x", string.byte(character))
		end)
	)
end

local function fromHex(hex: string): string?
	if #hex % 2 ~= 0 or string.find(hex, "[^%x]") ~= nil then
		return nil
	end
	return (
		string.gsub(hex, "%x%x", function(pair: string): string
			return string.char(tonumber(pair, 16) :: number)
		end)
	)
end

local function checksum(text: string): string
	local first, second = 1, 0
	for index = 1, #text do
		first = (first + string.byte(text, index)) % 65521
		second = (second + first) % 65521
	end
	return string.format("%04x%04x", second, first)
end

local function publisher(
	runId: string,
	token: string,
	encode: (unknown) -> string,
	emit: (string) -> ()
): Core.RunProgress
	assert(token ~= "" and string.find(token, "[^%w]") == nil, "progress token must be alphanumeric")
	return Core.progress.create(runId, function(event: Core.ProgressEvent)
		local hex = toHex(encode(event))
		local payload = ("%s|%d|%s|%s"):format(token, #hex, checksum(hex), hex)
		for _, line in Core.frame(TAG, payload, FRAME_LIMIT) do
			emit(line)
		end
	end)
end

local function collect(bytes: string, token: string, runId: string, decode: (string) -> unknown): Collected
	local seen: { [number]: boolean } = {}
	local result: Collected = { events = {}, rejected = 0, foreign = 0, first = nil }
	local function reject(reason: string)
		result.rejected += 1
		if result.first == nil then
			result.first = reason
		end
	end
	for _, record in Core.extract(bytes, TAG) do
		local frameToken, length, sum, hex = string.match(record.payload, "^(%w+)|(%d+)|(%x+)|(.*)$")
		if record.chunkIndex ~= nil or frameToken == nil then
			reject "a progress frame is malformed or chunked"
		elseif frameToken ~= token then
			result.foreign += 1
		else
			local body = hex :: string
			if tonumber(length) ~= #body or checksum(body) ~= sum then
				reject "a progress frame failed its length or checksum; the console altered it"
			else
				local text = fromHex(body)
				local decoded, value = pcall(decode, text or "")
				if not decoded or text == nil then
					reject "a progress frame did not decode"
				else
					local valid, event = pcall(Core.progress.valid, value, runId)
					if not valid then
						reject("a progress frame is not a valid event of this run: " .. tostring(event))
					elseif not seen[(event :: Core.ProgressEvent).sequence] then
						seen[(event :: Core.ProgressEvent).sequence] = true
						table.insert(result.events, event :: Core.ProgressEvent)
					end
				end
			end
		end
	end
	table.sort(result.events, function(left, right)
		return left.sequence < right.sequence
	end)
	return result
end

return { TAG = TAG, publisher = publisher, collect = collect, toHex = toHex }
