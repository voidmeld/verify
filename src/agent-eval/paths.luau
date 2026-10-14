--!strict

local function normalize(path: string): string
	return (string.gsub(path, "\\", "/"))
end

local function absolute(path: string): boolean
	local value = normalize(path)
	return string.sub(value, 1, 1) == "/" or string.match(value, "^%a:/") ~= nil
end

local function join(base: string, child: string): string
	local tail = normalize(child)
	if absolute(tail) or base == "" or base == "." then
		return tail
	end
	local head = normalize(base)
	if string.sub(head, -1) == "/" then
		return head .. tail
	end
	return head .. "/" .. tail
end

local function parent(path: string): string
	local value = normalize(path)
	local found = string.match(value, "^(.*)/[^/]*$")
	if found == nil then
		return "."
	end
	if found == "" then
		return "/"
	end
	return found
end

local function leaf(path: string): string
	local value = normalize(path)
	return string.match(value, "([^/]*)$") or value
end

local function contained(path: string): boolean
	local value = normalize(path)
	if absolute(value) then
		return false
	end
	for segment in string.gmatch(value, "[^/]+") do
		if segment == ".." then
			return false
		end
	end
	return true
end

return {
	normalize = normalize,
	absolute = absolute,
	join = join,
	parent = parent,
	leaf = leaf,
	contained = contained,
}
