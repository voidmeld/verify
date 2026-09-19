--!strict

export type Node = any

export type Owner = any

export type TransportRecord = {
	payload: string,
	ordinal: number,
	chunkIndex: number?,
	chunkCount: number?,
}

export type Transport = {
	frame: (tag: string, payload: string, maxPayloadBytes: number?) -> { string },
	extract: (bytes: string, tag: string) -> { TransportRecord },
	reassemble: (records: { TransportRecord }) -> (string?, string?),
}

export type Record = {
	payload: string,
	ordinal: number,
}

export type Wire = {
	frame: (tag: string, payload: string) -> { string },
	emit: (tag: string, payload: string, sink: (line: string) -> ()) -> (),
	records: (bytes: string, tag: string) -> ({ Record }, string?),
	payloads: (bytes: string, tag: string) -> ({ string }, string?),
	payload: (bytes: string, tag: string) -> (string?, string?),
	present: (bytes: string, tag: string) -> boolean,
}

export type ReportLimits = {
	depth: number,
	entries: number,
	stringBytes: number,
	stringLength: number,
}

export type Marker = {
	t: number,
	kind: string,
	target: string,
	source: string?,
}

export type MarkerLimits = {
	count: number,
	seconds: number,
	targetBytes: number,
	sourceBytes: number,
}

export type MarkerOptions = {
	kinds: { string },
	limits: MarkerLimits?,
}

export type ValueNames = {
	folder: string,
	runId: string,
	results: string,
	done: string,
}

export type Seam = {
	createFolder: (name: string) -> Node,
	writeString: (folder: Node, name: string, value: string) -> (),
	writeBool: (folder: Node, name: string, value: boolean) -> (),
	dispose: (() -> ())?,
}

export type SeamDeps = {
	createOwner: () -> Owner,
	createChild: (owner: Owner) -> Owner,
	dispose: (owner: Owner) -> (),
	custodyOf: (node: Node) -> string,
	borrowedCustody: string,
	createNode: (owner: Owner, parent: Node, className: string, name: string, value: any?) -> Node,
	adopt: (owner: Owner, node: Node) -> (),
	findChild: (parent: Node, name: string) -> Node?,
	children: (node: Node) -> { Node },
	isClass: (node: Node, className: string) -> boolean,
	setValue: (node: Node, value: any) -> (),
}

export type SeamState = {
	createFolder: (name: string) -> Node,
	writeValue: (folder: Node, name: string, value: any, className: string) -> (),
	dispose: () -> (),
}

export type Acquire = (parent: Node) -> (() -> (), SeamState)

local ENCODED_TAG_SUFFIX = "~enc1"

local DEFAULT_REPORT_LIMITS: ReportLimits = table.freeze {
	depth = 6,
	entries = 4096,
	stringBytes = 65536,
	stringLength = 4096,
}

local DEFAULT_MARKER_LIMITS: MarkerLimits = table.freeze {
	count = 2048,
	seconds = 600,
	targetBytes = 128,
	sourceBytes = 64,
}

local FOLDER_CLASS = "Folder"
local STRING_VALUE_CLASS = "StringValue"
local BOOL_VALUE_CLASS = "BoolValue"

local REASONS = table.freeze {
	disposed = "observation_seam_disposed",
	existingFolder = "observation_sink_refuses_existing_folder",
	existingValue = "observation_sink_refuses_existing_value",
	replacement = "observation_sink_refuses_replacement",
}

local function encode(payload: string): string
	return (
		string.gsub(payload, '[%%\\"%c\127]', function(byte: string): string
			return ("%%%02X"):format(string.byte(byte) :: number)
		end)
	)
end

local function decode(payload: string): string
	return (
		string.gsub(payload, "%%(%x%x)", function(hex: string): string
			return string.char(tonumber(hex, 16) :: number)
		end)
	)
end

local function createWire(transport: Transport): Wire
	local function records(bytes: string, tag: string): ({ Record }, string?)
		local grouped: { Record } = {}
		local defect: string? = nil
		local defectOrdinal = math.huge

		local function harvest(searchTag: string, encoded: boolean)
			local pending: { TransportRecord } = {}

			local function close(group: { TransportRecord })
				local payload, reason = transport.reassemble(group)
				if payload == nil then
					if group[1].ordinal < defectOrdinal then
						defect = reason
						defectOrdinal = group[1].ordinal
					end
					return
				end
				local whole = payload :: string
				table.insert(
					grouped,
					{ payload = if encoded then decode(whole) else whole, ordinal = group[1].ordinal }
				)
			end

			for _, record in transport.extract(bytes, searchTag) do
				if record.chunkIndex == nil then
					close { record }
					continue
				end
				table.insert(pending, record)
				if record.chunkIndex == record.chunkCount then
					close(pending)
					pending = {}
				end
			end
			if #pending > 0 then
				close(pending)
			end
		end

		harvest(tag, false)
		harvest(tag .. ENCODED_TAG_SUFFIX, true)
		table.sort(grouped, function(left: Record, right: Record): boolean
			return left.ordinal < right.ordinal
		end)
		return grouped, defect
	end

	local function payloads(bytes: string, tag: string): ({ string }, string?)
		local found, defect = records(bytes, tag)
		local result: { string } = table.create(#found)
		for _, record in found do
			table.insert(result, record.payload)
		end
		return result, defect
	end

	return table.freeze {
		frame = function(tag: string, payload: string): { string }
			return transport.frame(tag, payload)
		end,
		emit = function(tag: string, payload: string, sink: (line: string) -> ())
			for _, line in transport.frame(tag .. ENCODED_TAG_SUFFIX, encode(payload)) do
				sink(line)
			end
		end,
		records = records,
		payloads = payloads,
		payload = function(bytes: string, tag: string): (string?, string?)
			local found, defect = records(bytes, tag)
			if #found == 0 then
				return nil, if defect ~= nil then defect else "no tagged record was emitted"
			end
			return found[1].payload, defect
		end,
		present = function(bytes: string, tag: string): boolean
			return #transport.extract(bytes, tag) > 0 or #transport.extract(bytes, tag .. ENCODED_TAG_SUFFIX) > 0
		end,
	}
end

local function boundedValue(value: unknown, limits: ReportLimits?): (boolean, string?)
	local selected = if limits ~= nil then limits else DEFAULT_REPORT_LIMITS
	local entries = 0
	local stringBytes = 0
	local seen: { [any]: boolean } = {}
	local function visit(current: any, depth: number): (boolean, string?)
		local valueType = type(current)
		if valueType == "nil" or valueType == "boolean" then
			return true, nil
		elseif valueType == "number" then
			return current == current and current ~= math.huge and current ~= -math.huge, "report_non_finite_number"
		elseif valueType == "string" then
			if #current > selected.stringLength then
				return false, "report_string_over_budget"
			end
			stringBytes += #current
			return stringBytes <= selected.stringBytes, "report_strings_over_budget"
		elseif valueType ~= "table" then
			return false, "report_invalid_value_type"
		end
		if depth > selected.depth then
			return false, "report_depth_over_budget"
		end
		if seen[current] then
			return false, "report_cycle"
		end
		seen[current] = true
		for key, child in current do
			entries += 1
			if entries > selected.entries then
				return false, "report_entries_over_budget"
			end
			local keyType = type(key)
			if keyType ~= "string" and keyType ~= "number" then
				return false, "report_invalid_key_type"
			end
			local keyOk, keyReason = visit(key, depth + 1)
			if not keyOk then
				return false, keyReason
			end
			local childOk, childReason = visit(child, depth + 1)
			if not childOk then
				return false, childReason
			end
		end
		seen[current] = nil
		return true, nil
	end
	return visit(value, 0)
end

local function markers(raw: unknown, options: MarkerOptions): ({ Marker }?, string?)
	if raw == nil then
		return {}, nil
	end
	if type(raw) ~= "table" then
		return nil, "input_markers_not_table"
	end
	local limits = if options.limits ~= nil then options.limits else DEFAULT_MARKER_LIMITS
	local allowed: { [string]: boolean } = {}
	for _, kind in options.kinds do
		allowed[kind] = true
	end

	local markerMap = raw :: { [any]: any }
	local markerCount = #(raw :: { any })
	if markerCount > limits.count then
		return nil, "input_markers_over_budget"
	end
	for key in markerMap do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return nil, "input_markers_not_array"
		end
		if key > markerCount then
			return nil, "input_markers_not_contiguous"
		end
	end

	local collected: { Marker } = {}
	local previousT: number? = nil
	for index = 1, markerCount do
		local rawMarker = markerMap[index]
		if type(rawMarker) ~= "table" then
			return nil, "input_marker_not_table"
		end
		local marker = rawMarker :: { [string]: any }
		local t = marker.t
		local kind = marker.kind
		local target = marker.target
		local source = marker.source
		if type(t) ~= "number" or t < 0 or t > limits.seconds or t == math.huge or t ~= t then
			return nil, "input_marker_invalid_t"
		end
		if previousT ~= nil and t <= previousT then
			return nil, "input_marker_time_not_increasing"
		end
		if type(kind) ~= "string" or not allowed[kind] then
			return nil, "input_marker_invalid_kind"
		end
		if type(target) ~= "string" or target == "" or #target > limits.targetBytes then
			return nil, "input_marker_invalid_target"
		end
		if source ~= nil and (type(source) ~= "string" or source == "" or #source > limits.sourceBytes) then
			return nil, "input_marker_invalid_source"
		end
		table.insert(collected, { t = t, kind = kind, target = target, source = source :: string? })
		previousT = t
	end
	return collected, nil
end

local function tally(results: { { ok: boolean } }): (number, number)
	local passed = 0
	local failed = 0
	for _, result in results do
		if result.ok then
			passed += 1
		else
			failed += 1
		end
	end
	return passed, failed
end

type PoolEntry = {
	value: any,
	references: number,
}

local function referencePool(create: (key: any) -> any, release: (value: any) -> ()): (key: any) -> (() -> (), any)
	local entries: { [any]: PoolEntry } = setmetatable({}, { __mode = "k" }) :: any
	return function(key: any): (() -> (), any)
		local entry = entries[key]
		if entry == nil then
			entry = { value = create(key), references = 0 }
			entries[key] = entry
		end
		local held = entry :: PoolEntry
		held.references += 1
		local released = false
		local function drop()
			if released then
				return
			end
			released = true
			held.references -= 1
			if held.references > 0 then
				return
			end
			entries[key] = nil
			release(held.value)
		end
		return drop, held.value
	end
end

local function createSeamState(parent: Node, deps: SeamDeps): SeamState
	local owner = deps.createOwner()
	local folderNode: Node = nil
	local folderOwner: Owner = nil
	local nodeOwners: { [Node]: Owner } = {}

	local function removeNode(node: Node)
		local nodeOwner = nodeOwners[node]
		if nodeOwner ~= nil then
			nodeOwners[node] = nil
			deps.dispose(nodeOwner)
			return
		end
		if deps.custodyOf(node) ~= deps.borrowedCustody then
			error(REASONS.replacement, 2)
		end
		local replacementOwner = deps.createChild(owner)
		local adopted, adoptFailure = pcall(function(): any
			deps.adopt(replacementOwner, node)
			return nil
		end)
		local disposed, disposeFailure = pcall(function(): any
			deps.dispose(replacementOwner)
			return nil
		end)
		if not adopted then
			error(adoptFailure, 0)
		end
		if not disposed then
			error(disposeFailure, 0)
		end
	end

	local function createFolder(name: string): Node
		if folderNode ~= nil and deps.findChild(parent, name) == folderNode then
			return folderNode
		end
		if folderOwner ~= nil then
			deps.dispose(folderOwner)
			folderOwner = nil
		end
		local existing = deps.findChild(parent, name)
		if existing ~= nil and deps.isClass(existing, FOLDER_CLASS) then
			if deps.custodyOf(existing) ~= deps.borrowedCustody then
				error(REASONS.existingFolder, 2)
			end
			for _, child in deps.children(existing) do
				removeNode(child)
			end
			folderNode = existing
			return existing
		elseif existing ~= nil then
			removeNode(existing)
		end
		local created = deps.createChild(owner)
		local ok, folder = pcall(deps.createNode, created, parent, FOLDER_CLASS, name, nil)
		if not ok then
			deps.dispose(created)
			error(folder, 0)
		end
		folderOwner = created
		folderNode = folder
		return folder
	end

	local function writeValue(folder: Node, name: string, value: any, className: string)
		local existing = deps.findChild(folder, name)
		if existing ~= nil and deps.isClass(existing, className) then
			if nodeOwners[existing] == nil and deps.custodyOf(existing) ~= deps.borrowedCustody then
				error(REASONS.existingValue, 2)
			end
			deps.setValue(existing, value)
			return
		elseif existing ~= nil then
			removeNode(existing)
		end
		local nodeOwner = deps.createChild(owner)
		local ok, node = pcall(deps.createNode, nodeOwner, folder, className, name, value)
		if not ok then
			deps.dispose(nodeOwner)
			error(node, 0)
		end
		nodeOwners[node] = nodeOwner
	end

	local function dispose()
		deps.dispose(owner)
		table.clear(nodeOwners)
		folderNode = nil
		folderOwner = nil
	end

	return table.freeze {
		createFolder = createFolder,
		writeValue = writeValue,
		dispose = dispose,
	}
end

local function pooledSeam(parent: Node, acquire: Acquire): Seam
	local drop, state = acquire(parent)
	local active = true
	local function requireActive()
		if not active then
			error(REASONS.disposed, 3)
		end
	end

	return table.freeze {
		createFolder = function(name: string): Node
			requireActive()
			return state.createFolder(name)
		end,
		writeString = function(folder: Node, name: string, value: string)
			requireActive()
			state.writeValue(folder, name, value, STRING_VALUE_CLASS)
		end,
		writeBool = function(folder: Node, name: string, value: boolean)
			requireActive()
			state.writeValue(folder, name, value, BOOL_VALUE_CLASS)
		end,
		dispose = function()
			if not active then
				return
			end
			active = false
			drop()
		end,
	}
end

local function arm(seam: Seam, names: ValueNames, runId: string): Node
	local folder = seam.createFolder(names.folder)
	seam.writeString(folder, names.runId, runId)
	seam.writeString(folder, names.results, "")
	seam.writeBool(folder, names.done, false)
	return folder
end

local function publish(seam: Seam, names: ValueNames, runId: string, payloadJson: string): Node
	local folder = seam.createFolder(names.folder)
	seam.writeString(folder, names.runId, runId)
	seam.writeString(folder, names.results, payloadJson)
	seam.writeBool(folder, names.done, true)
	return folder
end

return {
	ENCODED_TAG_SUFFIX = ENCODED_TAG_SUFFIX,
	DEFAULT_REPORT_LIMITS = DEFAULT_REPORT_LIMITS,
	DEFAULT_MARKER_LIMITS = DEFAULT_MARKER_LIMITS,
	REASONS = REASONS,
	encode = encode,
	decode = decode,
	createWire = createWire,
	boundedValue = boundedValue,
	markers = markers,
	tally = tally,
	referencePool = referencePool,
	createSeamState = createSeamState,
	pooledSeam = pooledSeam,
	arm = arm,
	publish = publish,
}
