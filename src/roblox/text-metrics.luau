--!strict

export type Row = {
	advances: { number },
	adjustments: { number },
	starts: { number }?,
	ends: { number }?,
	height: number?,
}
export type Face = { tokens: { string }, pairs: { { number } }, sizes: { Row } }
export type Model = {
	width: (text: string, size: number) -> number,
	height: (size: number) -> number,
	wrap: (text: string, size: number, limit: number) -> (number, number),
	truncate: (text: string, size: number, limit: number, lines: number, mode: string, wrapped: boolean) -> number?,
}

local ACCENTED = {}
for _, letter in
	{
		"é",
		"á",
		"í",
		"ó",
		"ú",
		"ñ",
		"ü",
		"ö",
		"ä",
		"ç",
		"è",
		"à",
		"ê",
		"ô",
		"ë",
		"ß",
		"É",
		"ð",
		"ĝ",
		"ş",
		"Ş",
		"ţ",
	}
do
	ACCENTED[letter] = true
end

local function letter(token: string): boolean
	return token:match "%a" ~= nil or ACCENTED[token] == true
end

local function create(face: Face): Model
	local indices: { [string]: number } = {}
	local sequences: { [string]: { string } } = {}
	for index, token in face.tokens do
		indices[token] = index
		local first = token:sub(1, 1)
		local entries = sequences[first] or {}
		table.insert(entries, token)
		sequences[first] = entries
	end
	for _, entries in sequences do
		table.sort(entries, function(left, right): boolean
			return #left > #right
		end)
	end
	local pairs: { [number]: { [number]: number } } = {}
	for index, pair in face.pairs do
		local row = pairs[pair[1]] or {}
		row[pair[2]] = index
		pairs[pair[1]] = row
	end
	local function exact(text: string, size: number): number
		local row = assert(face.sizes[math.clamp(math.floor(size), 1, 100)])
		local cursor, total = 1, 0
		local previous: number? = nil
		local first: number? = nil
		local latin = false
		local latinBoundary = 0
		while cursor <= #text do
			local token: string? = nil
			local entries: { string } = sequences[text:sub(cursor, cursor)] or {}
			for _, sequence in entries do
				if text:sub(cursor, cursor + #sequence - 1) == sequence then
					token = sequence
					break
				end
			end
			if token == nil then
				local ok, code = pcall(utf8.codepoint, text, cursor)
				error(
					string.format(
						"unsupported_text_metrics: character U+%04X at byte %d",
						if ok then code else string.byte(text, cursor),
						cursor
					),
					0
				)
			end
			local matched = assert(token)
			local index = indices[matched]
			first = first or index
			total += row.advances[index]
			local startsLatin = not latin and letter(matched)
			if startsLatin and previous and row.starts then
				latinBoundary = row.starts[index] + (if row.ends then row.ends[previous] else 0)
			end
			if previous and not startsLatin then
				local pair = (pairs[previous] or {})[index]
				if pair then
					total += row.adjustments[pair]
				end
			end
			latin = latin or startsLatin
			previous = index
			cursor += #matched
		end
		return total
			+ (if first and row.starts then row.starts[first] else 0)
			+ latinBoundary
			+ (if previous and row.ends then row.ends[previous] else 0)
			- (if previous and row.starts and letter(face.tokens[previous]) then row.starts[previous] else 0)
	end
	local function width(text: string, size: number): number
		return math.ceil(exact(text, size))
	end
	local function wrap(text: string, size: number, limit: number): (number, number)
		local maximum, count = 0, 0
		for _, paragraph in string.split(text, "\n") do
			if limit <= 0 then
				maximum = math.max(maximum, width(paragraph, size))
				count += 1
				continue
			end
			local line = paragraph:match "^ *" or ""
			local function finish(trim: boolean)
				local measured = width(line, size)
				if (trim or measured > limit) and line:match "[^ ]" then
					measured = width(line:gsub(" +$", ""), size)
				end
				maximum = math.max(maximum, measured)
				count += 1
			end
			local cursor = #line + 1
			while cursor <= #paragraph do
				local word, spaces = paragraph:match("^([^ ]+)( *)", cursor)
				assert(word and spaces)
				if width(word, size) > limit then
					error("unsupported_text_metrics: word exceeds wrap width", 0)
				end
				if line ~= "" and width(line .. word, size) > limit then
					finish(true)
					line = ""
				end
				line ..= word .. spaces
				cursor += #word + #spaces
			end
			finish(false)
		end
		return maximum, count
	end
	local function cut(text: string, size: number, limit: number, mode: string): number?
		local mark = exact("…", size)
		local function fits(prefix: string): boolean
			return exact(prefix, size) + mark <= limit
		end
		local function shown(prefix: string): number
			local result = width(prefix, size) + math.ceil(mark)
			if result >= limit - 1 then
				error("unsupported_text_metrics: truncation within a pixel of the limit", 0)
			end
			return result
		end
		if mode == "AtEnd" then
			local best: string? = nil
			for stop in text:gmatch "() " do
				local prefix = text:sub(1, stop - 1):gsub(" +$", "")
				if prefix ~= "" and fits(prefix) then
					best = prefix
				end
			end
			if best then
				return shown(best)
			end
		end
		local offsets: { number } = {}
		for position in utf8.codes(text) do
			table.insert(offsets, position)
		end
		for index = #offsets, 2, -1 do
			local prefix = text:sub(1, offsets[index] - 1)
			if fits(prefix) then
				return shown(prefix)
			end
		end
		return if mark <= limit then shown "" else 0
	end
	local function truncate(
		text: string,
		size: number,
		limit: number,
		lines: number,
		mode: string,
		wrapped: boolean
	): number?
		if text:find "\n" or lines < 1 then
			error("unsupported_text_metrics: truncated multi-paragraph text", 0)
		end
		if not wrapped or lines == 1 then
			return cut(text, size, limit, mode)
		end
		local kept: { string } = {}
		local line = text:match "^ *" or ""
		local cursor = #line + 1
		local rest = 1
		while cursor <= #text do
			local word, spaces = text:match("^([^ ]+)( *)", cursor)
			assert(word and spaces)
			if width(word, size) > limit then
				error("unsupported_text_metrics: word exceeds wrap width", 0)
			end
			if line ~= "" and width(line .. word, size) > limit then
				table.insert(kept, (line:gsub(" +$", "")))
				if #kept == lines - 1 then
					rest = cursor
					break
				end
				line = ""
			end
			line ..= word .. spaces
			cursor += #word + #spaces
		end
		if #kept < lines - 1 or rest == 1 and lines > 1 then
			return nil
		end
		local remainder = text:sub(rest)
		local last = cut(remainder, size, limit, mode)
		if last == nil then
			return nil
		end
		if mode == "AtEnd" then
			local natural = remainder:match "^[^ ]+" or ""
			for gap, word in remainder:sub(#natural + 1):gmatch "( *)([^ ]+)" do
				local next = natural .. assert(gap) .. assert(word)
				if width(next, size) > limit then
					break
				end
				natural = next
			end
			if last < width(natural, size) then
				error("unsupported_text_metrics: wrapped truncation shorter than its line", 0)
			end
		end
		local widest = last
		for _, entry in kept do
			widest = math.max(widest, width(entry, size))
		end
		return widest
	end
	local function height(size: number): number
		local index = math.clamp(math.floor(size), 1, 100)
		return face.sizes[index].height or index
	end
	return table.freeze { width = width, wrap = wrap, height = height, truncate = truncate }
end

return table.freeze { create = create }
