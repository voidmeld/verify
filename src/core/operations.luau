--!strict

local Types = require "./types"

export type Request = {
	kind: "action" | "query",
	actor: string,
	name: string,
	payload: unknown,
	deadline: number,
}
export type JudgmentRequest = {
	actor: string,
	checkpoint: string,
	criterion: string,
	artifacts: { Types.Artifact },
}
export type Judgment = Types.Judgment
export type Host = {
	name: string,
	capabilities: { string },
	environment: { [string]: string },
	now: () -> number,
	sleep: ((number) -> ())?,
	invoke: (request: Request) -> unknown,
	capture: ((actor: string, checkpoint: string) -> { Types.Artifact })?,
	judge: ((request: JudgmentRequest) -> Judgment)?,
	close: (() -> ())?,
}
export type Observation = Types.Observation
export type Checkpoint = Types.Checkpoint
export type Review = Types.Review
export type Measurement = Types.Measurement
export type Parity = {
	status: "passed" | "failed" | "unsupported",
	differences: { string },
}
export type Evidence = Types.Evidence

export type Operation<I, O> = {
	kind: "action" | "query",
	name: string,
	input: (unknown) -> I,
	output: (unknown) -> O,
}
export type Endpoint = { run: (unknown, Request) -> unknown, requires: { string }? }
export type Binding = { key: string, endpoint: Endpoint }
export type HostOptions = {
	name: string,
	environment: { [string]: string },
	now: () -> number,
	bound: { Binding },
	sleep: ((number) -> ())?,
	capture: ((actor: string, checkpoint: string) -> { Types.Artifact })?,
}

local function operation<I, O>(definition: Operation<I, O>): Operation<I, O>
	assert(definition.name ~= "", "operation needs a name")
	assert(definition.kind == "action" or definition.kind == "query", "invalid operation kind")
	return table.freeze(table.clone(definition))
end

local function bind<I, O>(definition: Operation<I, O>, body: (I, Request) -> O): Endpoint
	return {
		run = function(payload: unknown, request: Request): unknown
			assert(request.kind == definition.kind and request.name == definition.name, "operation binding mismatch")
			return definition.output(body(definition.input(payload), request))
		end,
	}
end

local function binding<I, O>(definition: Operation<I, O>, body: (I, Request) -> O): Binding
	return { key = definition.kind .. ":" .. definition.name, endpoint = bind(definition, body) }
end

local function host(options: HostOptions): Host
	local endpoints: { [string]: Endpoint } = {}
	local capabilities: { string } = {}
	for _, entry in options.bound do
		endpoints[entry.key] = entry.endpoint
		table.insert(capabilities, entry.key)
	end
	if options.capture ~= nil then
		table.insert(capabilities, "capture")
	end
	return {
		name = options.name,
		capabilities = capabilities,
		environment = options.environment,
		now = options.now,
		sleep = options.sleep,
		invoke = function(request: Request): unknown
			local endpoint = endpoints[request.kind .. ":" .. request.name]
			assert(endpoint ~= nil, "unavailable operation " .. request.name)
			return endpoint.run(request.payload, request)
		end,
		capture = options.capture,
	}
end

local function finite(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

local function snapshot(value: unknown, ancestors: { [unknown]: boolean }?): unknown
	local kind = type(value)
	if kind == "nil" or kind == "string" or kind == "boolean" then
		return value
	elseif kind == "number" then
		assert(finite(value :: number), "observations must be finite")
		return value
	end
	assert(kind == "table", "observations must be portable values")
	assert(((getmetatable :: unknown) :: (unknown) -> unknown)(value) == nil, "observations must be plain values")
	local numeric, named, count, maximum = false, false, 0, 0
	for key in value :: { [unknown]: unknown } do
		if type(key) == "number" then
			assert(key >= 1 and key % 1 == 0 and finite(key), "observations require dense arrays")
			numeric, count, maximum = true, count + 1, math.max(maximum, key)
		else
			assert(type(key) == "string", "observations require string keys")
			named = true
		end
	end
	assert(not (numeric and named) and count == maximum, "observations require a dense array or string map")
	local seen: { [unknown]: boolean } = ancestors or {}
	assert(not seen[value], "observations must not contain cycles")
	seen[value] = true
	local copy: { [string | number]: unknown } = {}
	for key, child in value :: { [unknown]: unknown } do
		assert(type(key) == "string" or type(key) == "number", "observation keys must be strings or numbers")
		if type(key) == "number" then
			assert(finite(key), "observation keys must be finite")
		end
		copy[key :: string | number] = snapshot(child, seen)
	end
	seen[value] = nil
	return table.freeze(copy)
end

return { operation = operation, bind = bind, binding = binding, host = host, snapshot = snapshot }
