--!strict

local Roblox = require "../src/roblox"
local Sink = require "../src/roblox/observation-sink"
local Verify = require "../src/core"

local TAG = "OBSERVE"

local NAMES: Roblox.ObservationValueNames = {
	folder = "SinkFolder",
	runId = "SinkRunId",
	results = "SinkResults",
	done = "SinkDone",
}

local MARKER_KINDS = { "tap", "key", "move" }

local function wire(): Roblox.ObservationWire
	return Roblox.observationWire {
		frame = Verify.frame,
		extract = Verify.extract,
		reassemble = Verify.reassemble,
	}
end

local function emitted(tag: string, payload: string): string
	local lines: { string } = {}
	wire().emit(tag, payload, function(line: string)
		table.insert(lines, line)
	end)
	return table.concat(lines, "\n")
end

type FakeNode = {
	className: string,
	name: string,
	value: unknown,
	parent: FakeNode?,
	children: { FakeNode },
	custody: string,
}

type FakeOwner = {
	id: number,
	disposed: boolean,
	nodes: { FakeNode },
	childOwners: { FakeOwner },
}

type Engine = {
	root: FakeNode,
	deps: Sink.SeamDeps<FakeNode, FakeOwner>,
	owners: { FakeOwner },
	adopted: { FakeNode },
}

local function node(className: string, name: string, custody: string?): FakeNode
	return {
		className = className,
		name = name,
		value = nil,
		parent = nil,
		children = {},
		custody = if custody ~= nil then custody else "owned",
	}
end

local function attach(parent: FakeNode, child: FakeNode)
	child.parent = parent
	table.insert(parent.children, child)
end

local function detach(child: FakeNode)
	local parent = child.parent
	if parent == nil then
		return
	end
	for index, existing in parent.children do
		if existing == child then
			table.remove(parent.children, index)
			break
		end
	end
	child.parent = nil
end

local function engine(): Engine
	local root = node("Folder", "Root", "borrowed")
	local owners: { FakeOwner } = {}
	local adopted: { FakeNode } = {}
	local nextId = 0

	local function newOwner(): FakeOwner
		nextId += 1
		local owner: FakeOwner = { id = nextId, disposed = false, nodes = {}, childOwners = {} }
		table.insert(owners, owner)
		return owner
	end

	local function disposeOwner(owner: FakeOwner)
		if owner.disposed then
			return
		end
		owner.disposed = true
		for _, child in owner.childOwners do
			disposeOwner(child)
		end
		for _, held in owner.nodes do
			detach(held)
		end
		table.clear(owner.nodes)
	end

	local deps: Sink.SeamDeps<FakeNode, FakeOwner> = {
		createOwner = newOwner,
		createChild = function(owner: FakeOwner): FakeOwner
			local child = newOwner()
			table.insert((owner :: FakeOwner).childOwners, child)
			return child
		end,
		dispose = function(owner: FakeOwner)
			disposeOwner(owner :: FakeOwner)
		end,
		custodyOf = function(target: FakeNode): string
			return (target :: FakeNode).custody
		end,
		borrowedCustody = "borrowed",
		createNode = function(
			owner: FakeOwner,
			parent: FakeNode,
			className: string,
			name: string,
			value: unknown
		): FakeNode
			local created = node(className, name, "borrowed")
			created.value = value
			attach(parent :: FakeNode, created)
			table.insert((owner :: FakeOwner).nodes, created)
			return created
		end,
		adopt = function(owner: FakeOwner, target: FakeNode)
			table.insert(adopted, target :: FakeNode)
			table.insert((owner :: FakeOwner).nodes, target :: FakeNode)
		end,
		findChild = function(parent: FakeNode, name: string): FakeNode?
			for _, child in (parent :: FakeNode).children do
				if child.name == name then
					return child
				end
			end
			return nil
		end,
		children = function(target: FakeNode): { FakeNode }
			local copied: { FakeNode } = {}
			for _, child in (target :: FakeNode).children do
				table.insert(copied, child)
			end
			return copied
		end,
		isClass = function(target: FakeNode, className: string): boolean
			return (target :: FakeNode).className == className
		end,
		setValue = function(target: FakeNode, value: unknown)
			(target :: FakeNode).value = value
		end,
	}

	return { root = root, deps = deps, owners = owners, adopted = adopted }
end

local function child(parent: FakeNode, name: string): FakeNode?
	for _, entry in parent.children do
		if entry.name == name then
			return entry
		end
	end
	return nil
end

local function seamOver(host: Engine): (Sink.Seam<FakeNode>, () -> number)
	local created = 0
	local acquire = Roblox.observationReferencePool(function(parent: FakeNode): Sink.SeamState<FakeNode>
		created += 1
		return Roblox.createObservationSeamState(parent, host.deps)
	end, function(state: Sink.SeamState<FakeNode>)
		state.dispose()
	end)
	return Roblox.pooledObservationSeam(host.root, acquire), function(): number
		return created
	end
end

return function(suite: Verify.Harness)
	suite:suite("roblox observation wire", function()
		suite:case("round-trips a payload whose bytes the plain frame cannot carry", function(check)
			local payload = 'line one\nline "two"\t%50\127'
			local bytes = emitted(TAG, payload)
			local recovered, defect = wire().payload(bytes, TAG)
			check:expect(defect):toEqual(nil)
			check:expect(recovered):toEqual(payload)
		end)

		suite:case("emits no raw control byte or quote on the wire", function(check)
			local bytes = emitted(TAG, 'a\nb"c\td')
			check:expect((string.find(bytes, '"', 1, true))):toEqual(nil)
			check:expect((string.find(bytes, "\t", 1, true))):toEqual(nil)
		end)

		suite:case("reads a plain unencoded record written under the bare tag", function(check)
			local bytes = table.concat(wire().frame(TAG, "plain"), "\n")
			local recovered = wire().payload(bytes, TAG)
			check:expect(recovered):toEqual "plain"
		end)

		suite:case("orders mixed plain and encoded records by emission ordinal", function(check)
			local lines: { string } = {}
			for _, line in wire().frame(TAG, "first") do
				table.insert(lines, line)
			end
			wire().emit(TAG, "second", function(line: string)
				table.insert(lines, line)
			end)
			for _, line in wire().frame(TAG, "third") do
				table.insert(lines, line)
			end
			local payloads = wire().payloads(table.concat(lines, "\n"), TAG)
			check:expect(#payloads):toEqual(3)
			check:expect(payloads[1]):toEqual "first"
			check:expect(payloads[2]):toEqual "second"
			check:expect(payloads[3]):toEqual "third"
		end)

		suite:case("reassembles a payload larger than one transport chunk", function(check)
			local payload = string.rep("chunked ", 400)
			local recovered, defect = wire().payload(emitted(TAG, payload), TAG)
			check:expect(defect):toEqual(nil)
			check:expect(recovered):toEqual(payload)
		end)

		suite:case("reports the reassembly defect when a chunk group is incomplete", function(check)
			local lines: { string } = {}
			wire().emit(TAG, string.rep("chunked ", 400), function(line: string)
				table.insert(lines, line)
			end)
			table.remove(lines, 2)
			local recovered, defect = wire().payload(table.concat(lines, "\n"), TAG)
			check:expect(recovered):toEqual(nil)
			assert(defect ~= nil, "expected a reassembly defect")
		end)

		suite:case("reports absence rather than erroring when nothing carries the tag", function(check)
			local recovered, defect = wire().payload("unrelated output", TAG)
			check:expect(recovered):toEqual(nil)
			check:expect(defect):toEqual "no tagged record was emitted"
			check:expect((wire().present("unrelated output", TAG))):toEqual(false)
		end)

		suite:case("sees a tag present in either the plain or the encoded form", function(check)
			check:expect((wire().present(emitted(TAG, "x"), TAG))):toEqual(true)
			check:expect((wire().present(table.concat(wire().frame(TAG, "x"), "\n"), TAG))):toEqual(true)
		end)
	end)

	suite:suite("roblox observation bounded values", function()
		suite:case("accepts a nested table inside every budget", function(check)
			local ok, reason = Roblox.boundedObservationValue { a = { b = { c = 1 } }, d = "text", e = true }
			check:expect(ok):toEqual(true)
			check:expect(reason):toEqual(nil)
		end)

		suite:case("refuses a value nested past the depth budget", function(check)
			local deep: unknown = "leaf"
			for _ = 1, 9 do
				deep = { deep }
			end
			local ok, reason = Roblox.boundedObservationValue(deep)
			check:expect(ok):toEqual(false)
			check:expect(reason):toEqual "report_depth_over_budget"
		end)

		suite:case("refuses a cycle instead of recursing forever", function(check)
			local cycle: { [string]: unknown } = {}
			cycle.self = cycle
			local ok, reason = Roblox.boundedObservationValue(cycle)
			check:expect(ok):toEqual(false)
			check:expect(reason):toEqual "report_cycle"
		end)

		suite:case("refuses a non-finite number", function(check)
			local ok, reason = Roblox.boundedObservationValue { value = math.huge }
			check:expect(ok):toEqual(false)
			check:expect(reason):toEqual "report_non_finite_number"
		end)

		suite:case("refuses a value type a receipt cannot serialize", function(check)
			local ok, reason = Roblox.boundedObservationValue { value = print }
			check:expect(ok):toEqual(false)
			check:expect(reason):toEqual "report_invalid_value_type"
		end)

		suite:case("refuses a key type a receipt cannot serialize", function(check)
			local keyed: { [unknown]: unknown } = {}
			keyed[true] = 1
			local ok, reason = Roblox.boundedObservationValue(keyed)
			check:expect(ok):toEqual(false)
			check:expect(reason):toEqual "report_invalid_key_type"
		end)

		suite:case("refuses one oversized string and the sum of many", function(check)
			local single, singleReason = Roblox.boundedObservationValue { value = string.rep("x", 4097) }
			check:expect(single):toEqual(false)
			check:expect(singleReason):toEqual "report_string_over_budget"
			local many: { string } = {}
			for _ = 1, 32 do
				table.insert(many, string.rep("y", 4000))
			end
			local sum, sumReason = Roblox.boundedObservationValue(many)
			check:expect(sum):toEqual(false)
			check:expect(sumReason):toEqual "report_strings_over_budget"
		end)

		suite:case("refuses more entries than the budget allows", function(check)
			local wide: { number } = {}
			for index = 1, 5000 do
				wide[index] = index
			end
			local ok, reason = Roblox.boundedObservationValue(wide)
			check:expect(ok):toEqual(false)
			check:expect(reason):toEqual "report_entries_over_budget"
		end)

		suite:case("honours an injected budget rather than the default", function(check)
			local ok, reason = Roblox.boundedObservationValue({ a = { b = { c = 1 } } }, {
				depth = 1,
				entries = 4096,
				stringBytes = 65536,
				stringLength = 4096,
			})
			check:expect(ok):toEqual(false)
			check:expect(reason):toEqual "report_depth_over_budget"
		end)
	end)

	suite:suite("roblox observation markers", function()
		suite:case("reads an absent list as no markers", function(check)
			local read, reason = Roblox.observationMarkers(nil, { kinds = MARKER_KINDS })
			check:expect(reason):toEqual(nil)
			check:expect(#(read :: { Roblox.ObservationMarker })):toEqual(0)
		end)

		suite:case("keeps time, kind, target, and source of each accepted marker", function(check)
			local raw: { unknown } = {
				{ t = 0.5, kind = "tap", target = "button", source = "touch" },
				{ t = 1.5, kind = "key", target = "W" },
			}
			local read = Roblox.observationMarkers(raw, { kinds = MARKER_KINDS })
			local markers = read :: { Roblox.ObservationMarker }
			check:expect(#markers):toEqual(2)
			check:expect(markers[1].source):toEqual "touch"
			check:expect(markers[2].kind):toEqual "key"
			check:expect(markers[2].source):toEqual(nil)
		end)

		suite:case("refuses a list that is not a dense array", function(check)
			local sparse: { [unknown]: unknown } = {}
			sparse[2] = { t = 1, kind = "tap", target = "a" }
			local read, reason = Roblox.observationMarkers(sparse, { kinds = MARKER_KINDS })
			check:expect(read):toEqual(nil)
			check:expect(reason):toEqual "input_markers_not_contiguous"
		end)

		suite:case("refuses markers whose times do not strictly increase", function(check)
			local read, reason = Roblox.observationMarkers({
				{ t = 1, kind = "tap", target = "a" },
				{ t = 1, kind = "tap", target = "b" },
			}, { kinds = MARKER_KINDS })
			check:expect(read):toEqual(nil)
			check:expect(reason):toEqual "input_marker_time_not_increasing"
		end)

		suite:case("refuses a kind the caller did not declare", function(check)
			local read, reason = Roblox.observationMarkers(
				{ { t = 1, kind = "scroll", target = "a" } },
				{ kinds = MARKER_KINDS }
			)
			check:expect(read):toEqual(nil)
			check:expect(reason):toEqual "input_marker_invalid_kind"
		end)

		suite:case("refuses an out-of-range time and an oversized target", function(check)
			local late, lateReason = Roblox.observationMarkers(
				{ { t = 601, kind = "tap", target = "a" } },
				{ kinds = MARKER_KINDS }
			)
			check:expect(late):toEqual(nil)
			check:expect(lateReason):toEqual "input_marker_invalid_t"
			local wide, wideReason = Roblox.observationMarkers(
				{ { t = 1, kind = "tap", target = string.rep("t", 129) } },
				{ kinds = MARKER_KINDS }
			)
			check:expect(wide):toEqual(nil)
			check:expect(wideReason):toEqual "input_marker_invalid_target"
		end)

		suite:case("refuses an empty source string and a list over the count budget", function(check)
			local sourced, sourceReason = Roblox.observationMarkers(
				{ { t = 1, kind = "tap", target = "a", source = "" } },
				{ kinds = MARKER_KINDS }
			)
			check:expect(sourced):toEqual(nil)
			check:expect(sourceReason):toEqual "input_marker_invalid_source"
			local many: { unknown } = {}
			for index = 1, 3 do
				many[index] = { t = index, kind = "tap", target = "a" }
			end
			local capped, cappedReason = Roblox.observationMarkers(many, {
				kinds = MARKER_KINDS,
				limits = { count = 2, seconds = 600, targetBytes = 128, sourceBytes = 64 },
			})
			check:expect(capped):toEqual(nil)
			check:expect(cappedReason):toEqual "input_markers_over_budget"
		end)

		suite:case("refuses a list that is not a table at all", function(check)
			local read, reason = Roblox.observationMarkers("markers", { kinds = MARKER_KINDS })
			check:expect(read):toEqual(nil)
			check:expect(reason):toEqual "input_markers_not_table"
		end)
	end)

	suite:suite("roblox observation tally", function()
		suite:case("counts passing and failing rows without reading their names", function(check)
			local passed, failed = Roblox.tallyObservations {
				{ ok = true },
				{ ok = false },
				{ ok = true },
			}
			check:expect(passed):toEqual(2)
			check:expect(failed):toEqual(1)
		end)
	end)

	suite:suite("roblox observation seam", function()
		suite:case("arms a run with an empty result and an unset done flag", function(check)
			local host = engine()
			local seam = seamOver(host)
			Roblox.armObservationSink(seam, NAMES, "run-1")
			local folder = child(host.root, NAMES.folder) :: FakeNode
			check:expect(folder.className):toEqual "Folder"
			check:expect((child(folder, NAMES.runId) :: FakeNode).value):toEqual "run-1"
			check:expect((child(folder, NAMES.results) :: FakeNode).value):toEqual ""
			check:expect((child(folder, NAMES.done) :: FakeNode).value):toEqual(false)
		end)

		suite:case("publishes the payload and sets done on the same folder it armed", function(check)
			local host = engine()
			local seam = seamOver(host)
			Roblox.armObservationSink(seam, NAMES, "run-1")
			local armedFolder = child(host.root, NAMES.folder) :: FakeNode
			Roblox.publishObservations(seam, NAMES, "run-1", '{"passed":1}')
			local folder = child(host.root, NAMES.folder) :: FakeNode
			check:expect(folder):toEqual(armedFolder)
			check:expect((child(folder, NAMES.results) :: FakeNode).value):toEqual '{"passed":1}'
			check:expect((child(folder, NAMES.done) :: FakeNode).value):toEqual(true)
			check:expect(#host.root.children):toEqual(1)
		end)

		suite:case("writes value classes the caller asked for", function(check)
			local host = engine()
			local seam = seamOver(host)
			Roblox.armObservationSink(seam, NAMES, "run-1")
			local folder = child(host.root, NAMES.folder) :: FakeNode
			check:expect((child(folder, NAMES.runId) :: FakeNode).className):toEqual "StringValue"
			check:expect((child(folder, NAMES.done) :: FakeNode).className):toEqual "BoolValue"
		end)

		suite:case("clears a borrowed folder left behind by an earlier run", function(check)
			local host = engine()
			local stale = node("Folder", NAMES.folder, "borrowed")
			attach(host.root, stale)
			attach(stale, node("StringValue", "Leftover", "borrowed"))
			local seam = seamOver(host)
			Roblox.armObservationSink(seam, NAMES, "run-2")
			check:expect((child(stale, "Leftover"))):toEqual(nil)
			check:expect((child(host.root, NAMES.folder))):toEqual(stale)
			check:expect(#host.adopted):toEqual(1)
		end)

		suite:case("refuses an existing folder the host does not lend", function(check)
			local host = engine()
			attach(host.root, node("Folder", NAMES.folder, "owned"))
			local seam = seamOver(host)
			local ok, failure = pcall(Roblox.armObservationSink, seam, NAMES, "run-3")
			check:expect(ok):toEqual(false)
			assert(
				string.find(tostring(failure), Roblox.OBSERVATION_SINK_REASONS.existingFolder, 1, true) ~= nil,
				"names the refusal"
			)
		end)

		suite:case("refuses an existing value node the host does not lend", function(check)
			local host = engine()
			local seam = seamOver(host)
			local folder = Roblox.armObservationSink(seam, NAMES, "run-4")
			attach(folder :: FakeNode, node("StringValue", "Other", "owned"))
			local ok, failure = pcall(function()
				seam.writeString(folder, "Other", "value")
			end)
			check:expect(ok):toEqual(false)
			assert(
				string.find(tostring(failure), Roblox.OBSERVATION_SINK_REASONS.existingValue, 1, true) ~= nil,
				"names the refusal"
			)
		end)

		suite:case("refuses to replace a node the host does not lend", function(check)
			local host = engine()
			local stale = node("Folder", NAMES.folder, "borrowed")
			attach(host.root, stale)
			attach(stale, node("StringValue", "Leftover", "owned"))
			local seam = seamOver(host)
			local ok, failure = pcall(Roblox.armObservationSink, seam, NAMES, "run-9")
			check:expect(ok):toEqual(false)
			assert(
				string.find(tostring(failure), Roblox.OBSERVATION_SINK_REASONS.replacement, 1, true) ~= nil,
				"names the refusal"
			)
		end)

		suite:case("replaces a node of the wrong class rather than writing into it", function(check)
			local host = engine()
			local folder = node("Folder", NAMES.folder, "borrowed")
			attach(host.root, folder)
			attach(folder, node("IntValue", NAMES.runId, "borrowed"))
			local seam = seamOver(host)
			Roblox.armObservationSink(seam, NAMES, "run-5")
			local written = child(folder, NAMES.runId) :: FakeNode
			check:expect(written.className):toEqual "StringValue"
			check:expect(written.value):toEqual "run-5"
		end)

		suite:case("shares one state between seams over the same parent and disposes once", function(check)
			local host = engine()
			local first, created = seamOver(host)
			local acquire = Roblox.observationReferencePool(function(parent: FakeNode): Sink.SeamState<FakeNode>
				return Roblox.createObservationSeamState(parent, host.deps)
			end, function(state: Sink.SeamState<FakeNode>)
				state.dispose()
			end)
			local second = Roblox.pooledObservationSeam(host.root, acquire)
			local third = Roblox.pooledObservationSeam(host.root, acquire)
			Roblox.armObservationSink(second, NAMES, "run-6")
			Roblox.armObservationSink(third, NAMES, "run-6");
			(second.dispose :: () -> ())()
			check:expect(child(host.root, NAMES.folder) ~= nil):toEqual(true);
			(third.dispose :: () -> ())()
			check:expect((child(host.root, NAMES.folder))):toEqual(nil)
			check:expect((created())):toEqual(1)
			assert(first ~= second, "each caller holds its own seam handle")
		end)

		suite:case("refuses every write after the seam is disposed", function(check)
			local host = engine()
			local seam = seamOver(host);
			(seam.dispose :: () -> ())()
			local ok, failure = pcall(Roblox.armObservationSink, seam, NAMES, "run-7")
			check:expect(ok):toEqual(false)
			assert(
				string.find(tostring(failure), Roblox.OBSERVATION_SINK_REASONS.disposed, 1, true) ~= nil,
				"names the refusal"
			)
		end)

		suite:case("ignores a second dispose", function(check)
			local host = engine()
			local seam = seamOver(host)
			Roblox.armObservationSink(seam, NAMES, "run-8");
			(seam.dispose :: () -> ())();
			(seam.dispose :: () -> ())()
			check:expect((child(host.root, NAMES.folder))):toEqual(nil)
		end)
	end)
end
