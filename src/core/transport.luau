--!strict

export type Record = {
	payload: string,
	ordinal: number,
	chunkIndex: number?,
	chunkCount: number?,
}

local DEFAULT_MAX_PAYLOAD_BYTES = 700

export type Segment = {
	index: number,
	count: number,
	digest: string,
	totalDigest: string,
	totalBytes: number,
	payload: string,
}

local function fingerprint(text: string): string
	local hash = 2166136261
	for index = 1, #text do
		hash = bit32.bxor(hash, string.byte(text, index))
		hash = bit32.band(hash * 16777619, 0xFFFFFFFF)
	end
	return ("%08x-%d"):format(hash, #text)
end

local function checkedTag(tag: string): string
	if tag == "" then
		error("transport tag must not be empty", 3)
	end
	if string.find(tag, "|", 1, true) ~= nil then
		error("transport tag must not contain the field separator", 3)
	end
	return tag
end

local function frame(tag: string, payload: string, maxPayloadBytes: number?): { string }
	checkedTag(tag)
	local limit = if maxPayloadBytes ~= nil then maxPayloadBytes else DEFAULT_MAX_PAYLOAD_BYTES
	if limit <= 0 or limit % 1 ~= 0 then
		error("transport chunk size must be a positive integer", 2)
	end
	if #payload <= limit then
		return { tag .. "|" .. payload }
	end
	local count = math.ceil(#payload / limit)
	local lines: { string } = table.create(count)
	for index = 1, count do
		local first = (index - 1) * limit + 1
		local last = math.min(index * limit, #payload)
		table.insert(lines, ("%s|chunk|%d/%d|%s"):format(tag, index, count, string.sub(payload, first, last)))
	end
	return lines
end

local function extract(bytes: string, tag: string): { Record }
	checkedTag(tag)
	local prefix = tag .. "|"
	local records: { Record } = {}
	local ordinal = 0
	for line in string.gmatch(string.gsub(bytes, "\r\n", "\n") .. "\n", "(.-)\n") do
		ordinal += 1
		local start = string.find(line, prefix, 1, true)
		if start == nil then
			continue
		end
		local body = string.sub(line, start + #prefix)
		local chunkIndex, chunkCount, rest = string.match(body, "^chunk|(%d+)/(%d+)|(.*)$")
		if chunkIndex ~= nil then
			table.insert(records, {
				payload = rest :: string,
				ordinal = ordinal,
				chunkIndex = tonumber(chunkIndex),
				chunkCount = tonumber(chunkCount),
			})
		else
			table.insert(records, { payload = body, ordinal = ordinal })
		end
	end
	return records
end

local function reassemble(records: { Record }): (string?, string?)
	if #records == 0 then
		return nil, "no tagged record was emitted"
	end
	local whole: { Record } = {}
	local chunks: { Record } = {}
	for _, record in records do
		if record.chunkIndex ~= nil then
			table.insert(chunks, record)
		else
			table.insert(whole, record)
		end
	end
	if #whole > 0 and #chunks > 0 then
		return nil, ("mixed framing: %d whole record(s) and %d chunk(s) carry the same tag"):format(#whole, #chunks)
	end
	if #whole > 1 then
		return nil,
			("%d whole records carry the same tag; lines %d and %d"):format(#whole, whole[1].ordinal, whole[2].ordinal)
	end
	if #whole == 1 then
		return whole[1].payload, nil
	end

	local count = chunks[1].chunkCount :: number
	local seen: { [number]: Record } = {}
	for _, chunk in chunks do
		if chunk.chunkCount ~= count then
			return nil,
				("chunk counts disagree: line %d claims %d, line %d claims %d"):format(
					chunks[1].ordinal,
					count,
					chunk.ordinal,
					chunk.chunkCount :: number
				)
		end
		local index = chunk.chunkIndex :: number
		if index < 1 or index > count then
			return nil, ("chunk %d/%d on line %d is out of range"):format(index, count, chunk.ordinal)
		end
		local existing = seen[index]
		if existing ~= nil then
			if existing.payload ~= chunk.payload then
				return nil,
					("chunk %d/%d appears twice with different bytes, on lines %d and %d"):format(
						index,
						count,
						existing.ordinal,
						chunk.ordinal
					)
			end
			continue
		end
		seen[index] = chunk
	end
	local pieces: { string } = table.create(count)
	for index = 1, count do
		local chunk = seen[index]
		if chunk == nil then
			return nil, ("chunk %d of %d is missing"):format(index, count)
		end
		table.insert(pieces, chunk.payload)
	end
	return table.concat(pieces), nil
end

local function receipt(bytes: string, tag: string): (string?, string?)
	return reassemble(extract(bytes, tag))
end

local function segment(payload: string, maxBytes: number): { Segment }
	if maxBytes <= 0 or maxBytes % 1 ~= 0 then
		error("segment size must be a positive integer", 2)
	end
	local totalDigest = fingerprint(payload)
	local totalBytes = #payload
	if totalBytes == 0 then
		return {
			{ index = 1, count = 1, digest = fingerprint "", totalDigest = totalDigest, totalBytes = 0, payload = "" },
		}
	end
	local count = math.ceil(totalBytes / maxBytes)
	local segments: { Segment } = table.create(count)
	for index = 1, count do
		local first = (index - 1) * maxBytes + 1
		local last = math.min(index * maxBytes, totalBytes)
		local piece = string.sub(payload, first, last)
		table.insert(segments, {
			index = index,
			count = count,
			digest = fingerprint(piece),
			totalDigest = totalDigest,
			totalBytes = totalBytes,
			payload = piece,
		})
	end
	return segments
end

local function reassembleSegments(segments: { Segment }): (string?, string?)
	if #segments == 0 then
		return nil, "no segment was supplied"
	end
	local first = segments[1]
	if type(first) ~= "table" or type(first.count) ~= "number" then
		return nil, "a segment is malformed"
	end
	local count = first.count
	local totalDigest = first.totalDigest
	local totalBytes = first.totalBytes

	local seen: { [number]: Segment } = {}
	for _, piece in segments do
		if
			type(piece) ~= "table"
			or type(piece.index) ~= "number"
			or type(piece.count) ~= "number"
			or type(piece.digest) ~= "string"
			or type(piece.totalDigest) ~= "string"
			or type(piece.totalBytes) ~= "number"
			or type(piece.payload) ~= "string"
		then
			return nil, "a segment is malformed"
		end
		if piece.count ~= count then
			return nil, ("segments disagree about the total count: %d and %d"):format(count, piece.count)
		end
		if piece.totalDigest ~= totalDigest then
			return nil, "segments disagree about the whole payload's digest"
		end
		if piece.totalBytes ~= totalBytes then
			return nil, "segments disagree about the whole payload's length"
		end
		if piece.index < 1 or piece.index > count then
			return nil, ("segment %d/%d is out of range"):format(piece.index, count)
		end
		if fingerprint(piece.payload) ~= piece.digest then
			return nil, ("segment %d/%d failed its own digest check"):format(piece.index, count)
		end
		local existing = seen[piece.index]
		if existing ~= nil then
			if existing.payload ~= piece.payload then
				return nil, ("segment %d/%d appears twice with different bytes"):format(piece.index, count)
			end
			continue
		end
		seen[piece.index] = piece
	end

	local pieces: { string } = table.create(count)
	for index = 1, count do
		local piece = seen[index]
		if piece == nil then
			return nil, ("segment %d of %d is missing"):format(index, count)
		end
		table.insert(pieces, piece.payload)
	end
	local whole = table.concat(pieces)
	if #whole ~= totalBytes then
		return nil, ("reassembled %d bytes but the segments claimed %d: truncated"):format(#whole, totalBytes)
	end
	if fingerprint(whole) ~= totalDigest then
		return nil, "reassembled payload failed its whole-payload digest check"
	end
	return whole, nil
end

return {
	DEFAULT_MAX_PAYLOAD_BYTES = DEFAULT_MAX_PAYLOAD_BYTES,
	frame = frame,
	extract = extract,
	reassemble = reassemble,
	receipt = receipt,
	segment = segment,
	reassembleSegments = reassembleSegments,
}
