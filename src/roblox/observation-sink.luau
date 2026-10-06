--!strict

export type Node = unknown

export type Owner = unknown

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

export type Seam<N = Node> = {
	createFolder: (name: string) -> N,
	writeString: (folder: N, name: string, value: string) -> (),
	writeBool: (folder: N, name: string, value: boolean) -> (),
	dispose: (() -> ())?,
}

export type SeamDeps<N = Node, O = Owner> = {
	createOwner: () -> O,
	createChild: (owner: O) -> O,
	dispose: (owner: O) -> (),
	custodyOf: (node: N) -> string,
	borrowedCustody: string,
	createNode: (owner: O, parent: N, className: string, name: string, value: unknown?) -> N,
	adopt: (owner: O, node: N) -> (),
	findChild: (parent: N, name: string) -> N?,
	children: (node: N) -> { N },
	isClass: (node: N, className: string) -> boolean,
	setValue: (node: N, value: unknown) -> (),
}

export type SeamState<N = Node> = {
	createFolder: (name: string) -> N,
	writeValue: (folder: N, name: string, value: unknown, className: string) -> (),
	dispose: () -> (),
}

export type Acquire<N = Node> = (parent: N) -> (() -> (), SeamState<N>)

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
	local seen: { [unknown]: boolean } = {}
	local function visit(current: unknown, depth: number): (boolean, string?)
		if type(current) == "nil" or type(current) == "boolean" then
			return true, nil
		elseif type(current) == "number" then
			return current == current and current ~= math.huge and current ~= -math.huge, "report_non_finite_number"
		elseif type(current) == "string" then
			if #current > selected.stringLength then
				return false, "report_string_over_budget"
			end
			stringBytes += #current
			return stringBytes <= selected.stringBytes, "report_strings_over_budget"
		elseif type(current) ~= "table" then
			return false, "report_invalid_value_type"
		end
		if depth > selected.depth then
			return false, "report_depth_over_budget"
		end
		if seen[current] then
			return false, "report_cycle"
		end
		seen[current] = true
		for key, child in current :: { [unknown]: unknown } do
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

	local markerMap = raw :: { [unknown]: unknown }
	local markerCount = #(raw :: { unknown })
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
		local marker = rawMarker :: { [string]: unknown }
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

type PoolEntry<V> = {
	value: V,
	references: number,
}

local function referencePool<K, V>(create: (key: K) -> V, release: (value: V) -> ()): (key: K) -> (() -> (), V)
	local entries: { [K]: PoolEntry<V> } = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [K]: PoolEntry<V> }
	return function(key: K): (() -> (), V)
		local entry = entries[key]
		if entry == nil then
			entry = { value = create(key), references = 0 }
			entries[key] = entry
		end
		local held = entry :: PoolEntry<V>
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

local function createSeamState<N, O>(parent: N, deps: SeamDeps<N, O>): SeamState<N>
	local owner = deps.createOwner()
	local folderNode: N? = nil
	local folderOwner: O? = nil
	local nodeOwners: { [Node]: O } = {}

	local function removeNode(node: N)
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
		local adopted, adoptFailure = pcall(function(): unknown
			deps.adopt(replacementOwner, node)
			return nil
		end)
		local disposed, disposeFailure = pcall(function(): unknown
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

	local function createFolder(name: string): N
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

	local function writeValue(folder: N, name: string, value: unknown, className: string)
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

local function pooledSeam<N>(parent: N, acquire: Acquire<N>): Seam<N>
	local drop, state = acquire(parent)
	local active = true
	local function requireActive()
		if not active then
			error(REASONS.disposed, 3)
		end
	end

	return table.freeze {
		createFolder = function(name: string): N
			requireActive()
			return state.createFolder(name)
		end,
		writeString = function(folder: N, name: string, value: string)
			requireActive()
			state.writeValue(folder, name, value, STRING_VALUE_CLASS)
		end,
		writeBool = function(folder: N, name: string, value: boolean)
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

local function arm<N>(seam: Seam<N>, names: ValueNames, runId: string): N
	local folder = seam.createFolder(names.folder)
	seam.writeString(folder, names.runId, runId)
	seam.writeString(folder, names.results, "")
	seam.writeBool(folder, names.done, false)
	return folder
end

local function publish<N>(seam: Seam<N>, names: ValueNames, runId: string, payloadJson: string): N
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
