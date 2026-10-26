--!strict

local function lineEnd(source: string, index: number): number
	local ending = string.find(source, "\n", index, true)
	return if ending == nil then #source + 1 else ending
end

local function hashComments(source: string): { number }
	local found: { number } = {}
	local index = 1
	while index <= #source do
		local byte = string.byte(source, index)
		if byte == string.byte "'" or byte == string.byte '"' then
			local quote = byte
			index += 1
			while index <= #source do
				local current = string.byte(source, index)
				if current == string.byte "\\" then
					index += 2
				elseif current == quote then
					index += 1
					break
				elseif current == string.byte "\n" then
					break
				else
					index += 1
				end
			end
		elseif byte == string.byte "#" then
			if index ~= 1 or string.byte(source, index + 1) ~= string.byte "!" then
				table.insert(found, index)
			end
			index = lineEnd(source, index)
		else
			index += 1
		end
	end
	return found
end

local function withoutHashComments(source: string, starts: { number }): string
	local pieces: { string } = {}
	local cursor = 1
	for _, start in starts do
		local lineStart = start
		while lineStart > 1 and string.byte(source, lineStart - 1) ~= string.byte "\n" do
			lineStart -= 1
		end
		local prefix = string.sub(source, lineStart, start - 1)
		local finish = lineEnd(source, start)
		if string.match(prefix, "^[ \t]*$") ~= nil then
			table.insert(pieces, string.sub(source, cursor, lineStart - 1))
			cursor = math.min(finish + 1, #source + 1)
		else
			table.insert(pieces, string.sub(source, cursor, lineStart - 1) .. (string.gsub(prefix, "%s+$", "")))
			cursor = finish
		end
	end
	table.insert(pieces, string.sub(source, cursor))
	return table.concat(pieces)
end

return { hashComments = hashComments, withoutHashComments = withoutHashComments }
