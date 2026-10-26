--!strict

local Attachment = require "./attachment"
local Matchers = require "./matchers"
local Progress = require "./progress"
local Types = require "./types"
local Operations = require "./operations"
local Performance = require "./performance"

export type Status = Types.Status
export type Failure = Types.Failure
export type Origin = Types.Origin
export type CaseResult = Types.CaseResult
export type Report = Types.Report
export type Expectation = Matchers.Expectation

export type InvocationResult = {
	outcome: "returned" | "failed" | "timed_out" | "cancelled",
	error: unknown?,
}
export type Invoker = (phase: Types.InvocationPhase, run: () -> ()) -> InvocationResult

export type StepOptions = {
	actor: string?,
	run: () -> (),
}

export type Disposable<T = unknown> = {
	dispose: ((self: T) -> ())?,
	destroy: ((self: T) -> ())?,
}
export type Resource<T = unknown> = (() -> ()) | (T & { dispose: (T) -> () }) | (T & { destroy: (T) -> () })

export type Context = {
	id: string,
	unsupported: (self: Context, requirement: string) -> never,
	await: <I, O>(
		self: Context,
		actor: string,
		operation: Operations.Operation<I, O>,
		input: I,
		predicate: (O) -> boolean,
		pollSeconds: number,
		deadlineSeconds: number?
	) -> O,
	perform: <I, O>(
		self: Context,
		actor: string,
		operation: Operations.Operation<I, O>,
		input: I,
		deadlineSeconds: number?
	) -> O,
	checkpoint: (self: Context, actor: string, name: string) -> (),
	judge: (self: Context, actor: string, checkpoint: string, criterion: string) -> (),
	measure: (self: Context, actor: string, name: string, input: Performance.Input, limits: Performance.Limits) -> (),
	remainingSeconds: (self: Context) -> number,

	expect: (self: Context, value: unknown) -> Expectation,
	defer: (self: Context, cleanup: () -> ()) -> (),
	own: <T>(self: Context, resource: Resource<T>) -> (),
	skip: (self: Context, reason: string) -> never,
	step: (self: Context, name: string, definition: (() -> ()) | StepOptions) -> (),
	artifact: (self: Context, name: string, reference: string, mediaType: string?) -> (),
	attach: (self: Context, name: string, mediaType: string, text: string) -> (),
}

export type CaseRun = (context: Context) -> ()
export type CaseOptions = {
	timeoutSeconds: number?,
	cleanupTimeoutSeconds: number?,
	id: string?,
	run: CaseRun,
	requires: { string }?,
	tags: { string }?,
	limitations: { string }?,
}

export type SelectionPredicate = Types.SelectionPredicate
export type Selection = {
	ids: { string }?,
	suitePrefixes: { string }?,
	sources: { string }?,
	nameContains: string?,
	tags: { string }?,
	capabilities: { string }?,
	predicate: SelectionPredicate?,
	shard: { index: number, count: number }?,
	account: boolean?,
}

export type RunOptions = {
	bind: ((context: Context) -> Operations.Host)?,
	cancelled: (() -> boolean)?,
	executor: string,
	capabilities: { string }?,
	environment: { [string]: string }?,
	selection: Selection?,
	invoke: Invoker?,
	progress: Progress.Progress?,
	attachments: Attachment.Limits?,
}

export type Harness = {
	suite: (self: Harness, name: string, register: () -> ()) -> (),
	case: (self: Harness, name: string, definition: CaseRun | CaseOptions) -> (),
	skip: (self: Harness, name: string, reason: string, run: CaseRun?) -> (),
	beforeEach: (self: Harness, run: CaseRun) -> (),
	afterEach: (self: Harness, run: CaseRun) -> (),
	run: (self: Harness, options: RunOptions) -> Report,
}

export type SyntheticOptions = {
	executor: string,
	environment: { [string]: string }?,
	capabilities: { string }?,
	id: string,
	source: string?,
	name: string,
	status: "failed" | "skipped" | "unsupported" | "timed_out" | "cancelled",
	phase: Types.FailurePhase?,
	message: string?,
	skipReason: string?,
	missingCapabilities: { string }?,
	limitations: { string }?,
}

export type CaseEntry = {
	timeoutSeconds: number?,
	cleanupTimeoutSeconds: number?,
	id: string,
	name: string,
	source: string?,
	run: CaseRun,
	requires: { string },
	tags: { string },
	limitations: { string },
	skipReason: string?,
}

export type Suite = {
	name: string,
	parent: Suite?,
	children: { Suite },
	cases: { CaseEntry },
	beforeEach: { CaseRun },
	afterEach: { CaseRun },
}

local function checkedName(kind: string, name: string): string
	if name == "" then
		error(("%s name must not be empty"):format(kind), 3)
	end
	return name
end

local function ancestors(suite: Suite): { Suite }
	local values: { Suite } = {}
	local current: Suite? = suite
	while current ~= nil do
		table.insert(values, 1, current)
		current = current.parent
	end
	return values
end

local function suitePath(chain: { Suite }): { string }
	local path: { string } = {}
	for _, suite in chain do
		if suite.name ~= "" then
			table.insert(path, suite.name)
		end
	end
	return path
end

local function micros(seconds: number): number
	return math.max(0, math.floor(seconds * 1e6 + 0.5))
end

return { checkedName = checkedName, ancestors = ancestors, suitePath = suitePath, micros = micros }
