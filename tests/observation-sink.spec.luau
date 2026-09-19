--!strict

local test = require "@std/test"

local Roblox = require "../src/roblox"
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
	value: any,
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
	deps: Roblox.ObservationSeamDeps,
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

	local deps: Roblox.ObservationSeamDeps = {
		createOwner = newOwner,
		createChild = function(owner: any): any
			local child = newOwner()
			table.insert((owner :: FakeOwner).childOwners, child)
			return child
		end,
		dispose = function(owner: any)
			disposeOwner(owner :: FakeOwner)
		end,
		custodyOf = function(target: any): string
			return (target :: FakeNode).custody
		end,
		borrowedCustody = "borrowed",
		createNode = function(owner: any, parent: any, className: string, name: string, value: any): any
			local created = node(className, name, "borrowed")
			created.value = value
			attach(parent :: FakeNode, created)
			table.insert((owner :: FakeOwner).nodes, created)
			return created
		end,
		adopt = function(owner: any, target: any)
			table.insert(adopted, target :: FakeNode)
			table.insert((owner :: FakeOwner).nodes, target :: FakeNode)
		end,
		findChild = function(parent: any, name: string): any
			for _, child in (parent :: FakeNode).children do
				if child.name == name then
					return child
				end
			end
			return nil
		end,
		children = function(target: any): { any }
			local copied: { any } = {}
			for _, child in (target :: FakeNode).children do
				table.insert(copied, child)
			end
			return copied
		end,
		isClass = function(target: any, className: string): boolean
			return (target :: FakeNode).className == className
		end,
		setValue = function(target: any, value: any)
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

local function seamOver(host: Engine): (Roblox.ObservationSeam, () -> number)
	local created = 0
	local acquire = Roblox.observationReferencePool(function(parent: any): any
		created += 1
		return Roblox.createObservationSeamState(parent, host.deps)
	end, function(state: any)
		(state :: Roblox.ObservationSeamState).dispose()
	end)
	return Roblox.pooledObservationSeam(host.root, acquire), function(): number
		return created
	end
end

test.suite("roblox observation wire", function(suite)
	suite:case("round-trips a payload whose bytes the plain frame cannot carry", function(assert)
		local payload = 'line one\nline "two"\t%50\127'
		local bytes = emitted(TAG, payload)
		local recovered, defect = wire().payload(bytes, TAG)
		assert.eq(defect, nil)
		assert.eq(recovered, payload)
	end)

	suite:case("emits no raw control byte or quote on the wire", function(assert)
		local bytes = emitted(TAG, 'a\nb"c\td')
		assert.eq(string.find(bytes, '"', 1, true), nil)
		assert.eq(string.find(bytes, "\t", 1, true), nil)
	end)

	suite:case("reads a plain unencoded record written under the bare tag", function(assert)
		local bytes = table.concat(wire().frame(TAG, "plain"), "\n")
		local recovered = wire().payload(bytes, TAG)
		assert.eq(recovered, "plain")
	end)

	suite:case("orders mixed plain and encoded records by emission ordinal", function(assert)
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
		assert.eq(#payloads, 3)
		assert.eq(payloads[1], "first")
		assert.eq(payloads[2], "second")
		assert.eq(payloads[3], "third")
	end)

	suite:case("reassembles a payload larger than one transport chunk", function(assert)
		local payload = string.rep("chunked ", 400)
		local recovered, defect = wire().payload(emitted(TAG, payload), TAG)
		assert.eq(defect, nil)
		assert.eq(recovered, payload)
	end)

	suite:case("reports the reassembly defect when a chunk group is incomplete", function(assert)
		local lines: { string } = {}
		wire().emit(TAG, string.rep("chunked ", 400), function(line: string)
			table.insert(lines, line)
		end)
		table.remove(lines, 2)
		local recovered, defect = wire().payload(table.concat(lines, "\n"), TAG)
		assert.eq(recovered, nil)
		assert.that(defect ~= nil, "expected a reassembly defect")
	end)

	suite:case("reports absence rather than erroring when nothing carries the tag", function(assert)
		local recovered, defect = wire().payload("unrelated output", TAG)
		assert.eq(recovered, nil)
		assert.eq(defect, "no tagged record was emitted")
		assert.eq(wire().present("unrelated output", TAG), false)
	end)

	suite:case("sees a tag present in either the plain or the encoded form", function(assert)
		assert.eq(wire().present(emitted(TAG, "x"), TAG), true)
		assert.eq(wire().present(table.concat(wire().frame(TAG, "x"), "\n"), TAG), true)
	end)
end)

test.suite("roblox observation bounded values", function(suite)
	suite:case("accepts a nested table inside every budget", function(assert)
		local ok, reason = Roblox.boundedObservationValue { a = { b = { c = 1 } }, d = "text", e = true }
		assert.eq(ok, true)
		assert.eq(reason, nil)
	end)

	suite:case("refuses a value nested past the depth budget", function(assert)
		local deep: any = "leaf"
		for _ = 1, 9 do
			deep = { deep }
		end
		local ok, reason = Roblox.boundedObservationValue(deep)
		assert.eq(ok, false)
		assert.eq(reason, "report_depth_over_budget")
	end)

	suite:case("refuses a cycle instead of recursing forever", function(assert)
		local cycle: any = {}
		cycle.self = cycle
		local ok, reason = Roblox.boundedObservationValue(cycle)
		assert.eq(ok, false)
		assert.eq(reason, "report_cycle")
	end)

	suite:case("refuses a non-finite number", function(assert)
		local ok, reason = Roblox.boundedObservationValue { value = math.huge }
		assert.eq(ok, false)
		assert.eq(reason, "report_non_finite_number")
	end)

	suite:case("refuses a value type a receipt cannot serialize", function(assert)
		local ok, reason = Roblox.boundedObservationValue { value = print }
		assert.eq(ok, false)
		assert.eq(reason, "report_invalid_value_type")
	end)

	suite:case("refuses a key type a receipt cannot serialize", function(assert)
		local keyed: { [any]: any } = {}
		keyed[true] = 1
		local ok, reason = Roblox.boundedObservationValue(keyed)
		assert.eq(ok, false)
		assert.eq(reason, "report_invalid_key_type")
	end)

	suite:case("refuses one oversized string and the sum of many", function(assert)
		local single, singleReason = Roblox.boundedObservationValue { value = string.rep("x", 4097) }
		assert.eq(single, false)
		assert.eq(singleReason, "report_string_over_budget")
		local many: { string } = {}
		for _ = 1, 32 do
			table.insert(many, string.rep("y", 4000))
		end
		local sum, sumReason = Roblox.boundedObservationValue(many)
		assert.eq(sum, false)
		assert.eq(sumReason, "report_strings_over_budget")
	end)

	suite:case("refuses more entries than the budget allows", function(assert)
		local wide: { number } = {}
		for index = 1, 5000 do
			wide[index] = index
		end
		local ok, reason = Roblox.boundedObservationValue(wide)
		assert.eq(ok, false)
		assert.eq(reason, "report_entries_over_budget")
	end)

	suite:case("honours an injected budget rather than the default", function(assert)
		local ok, reason = Roblox.boundedObservationValue({ a = { b = { c = 1 } } }, {
			depth = 1,
			entries = 4096,
			stringBytes = 65536,
			stringLength = 4096,
		})
		assert.eq(ok, false)
		assert.eq(reason, "report_depth_over_budget")
	end)
end)

test.suite("roblox observation markers", function(suite)
	suite:case("reads an absent list as no markers", function(assert)
		local read, reason = Roblox.observationMarkers(nil, { kinds = MARKER_KINDS })
		assert.eq(reason, nil)
		assert.eq(#(read :: { Roblox.ObservationMarker }), 0)
	end)

	suite:case("keeps time, kind, target, and source of each accepted marker", function(assert)
		local raw: { any } = {
			{ t = 0.5, kind = "tap", target = "button", source = "touch" },
			{ t = 1.5, kind = "key", target = "W" },
		}
		local read = Roblox.observationMarkers(raw, { kinds = MARKER_KINDS })
		local markers = read :: { Roblox.ObservationMarker }
		assert.eq(#markers, 2)
		assert.eq(markers[1].source, "touch")
		assert.eq(markers[2].kind, "key")
		assert.eq(markers[2].source, nil)
	end)

	suite:case("refuses a list that is not a dense array", function(assert)
		local sparse: { [any]: any } = {}
		sparse[2] = { t = 1, kind = "tap", target = "a" }
		local read, reason = Roblox.observationMarkers(sparse, { kinds = MARKER_KINDS })
		assert.eq(read, nil)
		assert.eq(reason, "input_markers_not_contiguous")
	end)

	suite:case("refuses markers whose times do not strictly increase", function(assert)
		local read, reason = Roblox.observationMarkers({
			{ t = 1, kind = "tap", target = "a" },
			{ t = 1, kind = "tap", target = "b" },
		}, { kinds = MARKER_KINDS })
		assert.eq(read, nil)
		assert.eq(reason, "input_marker_time_not_increasing")
	end)

	suite:case("refuses a kind the caller did not declare", function(assert)
		local read, reason = Roblox.observationMarkers(
			{ { t = 1, kind = "scroll", target = "a" } },
			{ kinds = MARKER_KINDS }
		)
		assert.eq(read, nil)
		assert.eq(reason, "input_marker_invalid_kind")
	end)

	suite:case("refuses an out-of-range time and an oversized target", function(assert)
		local late, lateReason = Roblox.observationMarkers(
			{ { t = 601, kind = "tap", target = "a" } },
			{ kinds = MARKER_KINDS }
		)
		assert.eq(late, nil)
		assert.eq(lateReason, "input_marker_invalid_t")
		local wide, wideReason = Roblox.observationMarkers(
			{ { t = 1, kind = "tap", target = string.rep("t", 129) } },
			{ kinds = MARKER_KINDS }
		)
		assert.eq(wide, nil)
		assert.eq(wideReason, "input_marker_invalid_target")
	end)

	suite:case("refuses an empty source string and a list over the count budget", function(assert)
		local sourced, sourceReason = Roblox.observationMarkers(
			{ { t = 1, kind = "tap", target = "a", source = "" } },
			{ kinds = MARKER_KINDS }
		)
		assert.eq(sourced, nil)
		assert.eq(sourceReason, "input_marker_invalid_source")
		local many: { any } = {}
		for index = 1, 3 do
			many[index] = { t = index, kind = "tap", target = "a" }
		end
		local capped, cappedReason = Roblox.observationMarkers(many, {
			kinds = MARKER_KINDS,
			limits = { count = 2, seconds = 600, targetBytes = 128, sourceBytes = 64 },
		})
		assert.eq(capped, nil)
		assert.eq(cappedReason, "input_markers_over_budget")
	end)

	suite:case("refuses a list that is not a table at all", function(assert)
		local read, reason = Roblox.observationMarkers("markers", { kinds = MARKER_KINDS })
		assert.eq(read, nil)
		assert.eq(reason, "input_markers_not_table")
	end)
end)

test.suite("roblox observation tally", function(suite)
	suite:case("counts passing and failing rows without reading their names", function(assert)
		local passed, failed = Roblox.tallyObservations {
			{ ok = true },
			{ ok = false },
			{ ok = true },
		}
		assert.eq(passed, 2)
		assert.eq(failed, 1)
	end)
end)

test.suite("roblox observation seam", function(suite)
	suite:case("arms a run with an empty result and an unset done flag", function(assert)
		local host = engine()
		local seam = seamOver(host)
		Roblox.armObservationSink(seam, NAMES, "run-1")
		local folder = child(host.root, NAMES.folder) :: FakeNode
		assert.eq(folder.className, "Folder")
		assert.eq((child(folder, NAMES.runId) :: FakeNode).value, "run-1")
		assert.eq((child(folder, NAMES.results) :: FakeNode).value, "")
		assert.eq((child(folder, NAMES.done) :: FakeNode).value, false)
	end)

	suite:case("publishes the payload and sets done on the same folder it armed", function(assert)
		local host = engine()
		local seam = seamOver(host)
		Roblox.armObservationSink(seam, NAMES, "run-1")
		local armedFolder = child(host.root, NAMES.folder) :: FakeNode
		Roblox.publishObservations(seam, NAMES, "run-1", '{"passed":1}')
		local folder = child(host.root, NAMES.folder) :: FakeNode
		assert.eq(folder, armedFolder)
		assert.eq((child(folder, NAMES.results) :: FakeNode).value, '{"passed":1}')
		assert.eq((child(folder, NAMES.done) :: FakeNode).value, true)
		assert.eq(#host.root.children, 1)
	end)

	suite:case("writes value classes the caller asked for", function(assert)
		local host = engine()
		local seam = seamOver(host)
		Roblox.armObservationSink(seam, NAMES, "run-1")
		local folder = child(host.root, NAMES.folder) :: FakeNode
		assert.eq((child(folder, NAMES.runId) :: FakeNode).className, "StringValue")
		assert.eq((child(folder, NAMES.done) :: FakeNode).className, "BoolValue")
	end)

	suite:case("clears a borrowed folder left behind by an earlier run", function(assert)
		local host = engine()
		local stale = node("Folder", NAMES.folder, "borrowed")
		attach(host.root, stale)
		attach(stale, node("StringValue", "Leftover", "borrowed"))
		local seam = seamOver(host)
		Roblox.armObservationSink(seam, NAMES, "run-2")
		assert.eq(child(stale, "Leftover"), nil)
		assert.eq(child(host.root, NAMES.folder), stale)
		assert.eq(#host.adopted, 1)
	end)

	suite:case("refuses an existing folder the host does not lend", function(assert)
		local host = engine()
		attach(host.root, node("Folder", NAMES.folder, "owned"))
		local seam = seamOver(host)
		local ok, failure = pcall(Roblox.armObservationSink, seam, NAMES, "run-3")
		assert.eq(ok, false)
		assert.that(
			string.find(tostring(failure), Roblox.OBSERVATION_SINK_REASONS.existingFolder, 1, true) ~= nil,
			"names the refusal"
		)
	end)

	suite:case("refuses an existing value node the host does not lend", function(assert)
		local host = engine()
		local seam = seamOver(host)
		local folder = Roblox.armObservationSink(seam, NAMES, "run-4")
		attach(folder :: FakeNode, node("StringValue", "Other", "owned"))
		local ok, failure = pcall(function()
			seam.writeString(folder, "Other", "value")
		end)
		assert.eq(ok, false)
		assert.that(
			string.find(tostring(failure), Roblox.OBSERVATION_SINK_REASONS.existingValue, 1, true) ~= nil,
			"names the refusal"
		)
	end)

	suite:case("refuses to replace a node the host does not lend", function(assert)
		local host = engine()
		local stale = node("Folder", NAMES.folder, "borrowed")
		attach(host.root, stale)
		attach(stale, node("StringValue", "Leftover", "owned"))
		local seam = seamOver(host)
		local ok, failure = pcall(Roblox.armObservationSink, seam, NAMES, "run-9")
		assert.eq(ok, false)
		assert.that(
			string.find(tostring(failure), Roblox.OBSERVATION_SINK_REASONS.replacement, 1, true) ~= nil,
			"names the refusal"
		)
	end)

	suite:case("replaces a node of the wrong class rather than writing into it", function(assert)
		local host = engine()
		local folder = node("Folder", NAMES.folder, "borrowed")
		attach(host.root, folder)
		attach(folder, node("IntValue", NAMES.runId, "borrowed"))
		local seam = seamOver(host)
		Roblox.armObservationSink(seam, NAMES, "run-5")
		local written = child(folder, NAMES.runId) :: FakeNode
		assert.eq(written.className, "StringValue")
		assert.eq(written.value, "run-5")
	end)

	suite:case("shares one state between seams over the same parent and disposes once", function(assert)
		local host = engine()
		local first, created = seamOver(host)
		local acquire = Roblox.observationReferencePool(function(parent: any): any
			return Roblox.createObservationSeamState(parent, host.deps)
		end, function(state: any)
			(state :: Roblox.ObservationSeamState).dispose()
		end)
		local second = Roblox.pooledObservationSeam(host.root, acquire)
		local third = Roblox.pooledObservationSeam(host.root, acquire)
		Roblox.armObservationSink(second, NAMES, "run-6")
		Roblox.armObservationSink(third, NAMES, "run-6");
		(second.dispose :: () -> ())()
		assert.eq(child(host.root, NAMES.folder) ~= nil, true);
		(third.dispose :: () -> ())()
		assert.eq(child(host.root, NAMES.folder), nil)
		assert.eq(created(), 1)
		assert.that(first ~= second, "each caller holds its own seam handle")
	end)

	suite:case("refuses every write after the seam is disposed", function(assert)
		local host = engine()
		local seam = seamOver(host);
		(seam.dispose :: () -> ())()
		local ok, failure = pcall(Roblox.armObservationSink, seam, NAMES, "run-7")
		assert.eq(ok, false)
		assert.that(
			string.find(tostring(failure), Roblox.OBSERVATION_SINK_REASONS.disposed, 1, true) ~= nil,
			"names the refusal"
		)
	end)

	suite:case("ignores a second dispose", function(assert)
		local host = engine()
		local seam = seamOver(host)
		Roblox.armObservationSink(seam, NAMES, "run-8");
		(seam.dispose :: () -> ())();
		(seam.dispose :: () -> ())()
		assert.eq(child(host.root, NAMES.folder), nil)
	end)
end)
