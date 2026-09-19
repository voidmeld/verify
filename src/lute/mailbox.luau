--!strict

local RAISED_PREFIX = "verify-worker-raised: "

export type Names = {
	request: string,
	requestReady: string,
	response: string,
	sentinel: string,
}

local function names(directory: string, slot: number, sequence: number): Names
	local stem = ("%s/w%d-%d"):format(directory, slot, sequence)
	return {
		request = stem .. "-request.json",
		requestReady = stem .. "-request.done",
		response = stem .. "-response.json",
		sentinel = stem .. "-response.done",
	}
end

local function stopPath(directory: string): string
	return directory .. "/stop"
end

local function readyPath(directory: string, slot: number): string
	return ("%s/w%d-ready"):format(directory, slot)
end

return {
	RAISED_PREFIX = RAISED_PREFIX,
	names = names,
	stopPath = stopPath,
	readyPath = readyPath,
}
