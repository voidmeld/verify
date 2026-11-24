--!strict

local fs = require "@std/fs"

export type Tail = { consumed: number }

local function create(): Tail
	return { consumed = 0 }
end

local function fresh(path: string, tail: Tail): string?
	if not fs.exists(path) then
		return nil
	end
	local size = fs.metadata(path).size
	if size <= tail.consumed then
		return nil
	end
	local wanted = size - tail.consumed
	local handle = fs.open(path, "r")
	local buf = buffer.create(wanted)
	local read, count = pcall(function(): number
		return fs.readIntoBuffer(handle, buf, tail.consumed, wanted, 0)
	end)
	fs.close(handle)
	if not read then
		error(count, 0)
	end
	if count <= 0 then
		return nil
	end
	return buffer.readstring(buf, 0, count)
end

local function lines(path: string, tail: Tail): { string }
	local chunk = fresh(path, tail)
	if chunk == nil then
		return {}
	end
	local complete: { string } = {}
	local start = 1
	while true do
		local newline = string.find(chunk, "\n", start, true)
		if newline == nil then
			break
		end
		if newline > start then
			table.insert(complete, string.sub(chunk, start, newline - 1))
		end
		start = newline + 1
	end
	tail.consumed += start - 1
	return complete
end

return { create = create, lines = lines }
