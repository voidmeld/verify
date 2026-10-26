--!strict

local current: unknown = nil

local function set(harness: unknown)
	current = harness
end

local function get(): unknown
	return current
end

return { set = set, get = get }
