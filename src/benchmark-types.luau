--!strict

local Performance = require "./core/performance"

export type Unit = "seconds" | "milliseconds" | "microseconds"
export type Clock = () -> number
export type Metric = "p50" | "p95" | "p99" | "mean"
export type HeapReading = { before: number, after: number, growth: number, unit: string }

export type Budget = {
	p50: number?,
	p95: number?,
	p99: number?,
	maximum: number?,
}

export type Yardstick = {
	run: () -> (),
	samples: number,
	iterations: number?,
	warmup: number?,
	maxSpread: number,
	maxDrift: number,
	driftStatistic: YardstickStatistic?,
	driftBase: DriftBase?,
}

export type DriftBase = "first" | "mean"

export type Baseline = {
	identity: string,
	environment: string,
	unit: Unit,
	metric: Metric,
	value: number?,
	samples: { number }?,
	tolerance: number,
	yardstick: number?,
	yardstickStatistic: YardstickStatistic?,
	floor: Floor?,
}

export type YardstickStatistic = "median" | "p95"

export type Floor = {
	limit: number,
	metric: Metric?,
	recorded: number?,
}

export type Heap = {
	probe: () -> number?,
	unit: string,
	maximumGrowth: number?,
}

export type Judgment = {
	phase: string?,
	samples: { number },
	summary: Performance.Summary,
	series: Performance.Series,
	unit: Unit,
	yardstickBefore: { number },
	yardstickAfter: { number },
	yardstickBeforeSummary: Performance.Summary,
	yardstickAfterSummary: Performance.Summary,
	heap: HeapReading?,
}

export type Sampler = {
	series: (name: string, values: { number }) -> (),
}

export type WarmupScope = "workload" | "sample"

export type Phase = {
	name: string,
	run: (state: unknown, sampler: Sampler) -> (),
	budget: Budget?,
	maxSpread: number?,
	baseline: Baseline?,
	judge: ((view: Judgment) -> string?)?,
}

export type Spec = {
	name: string,
	unit: Unit,
	workload: ((state: unknown, sampler: Sampler) -> ())?,
	phases: { Phase }?,
	finalize: ((state: unknown, sampler: Sampler) -> ())?,
	warmup: number,
	warmupScope: WarmupScope?,
	samples: number,
	iterations: number?,
	percentiles: { number }?,
	budget: Budget?,
	environment: { observed: string, accepted: { string }? },
	maxSpread: number?,
	yardstick: Yardstick?,
	baseline: Baseline?,
	acceptedBaselines: { string }?,
	deadlineSeconds: number?,
	clock: Clock?,
	signal: string?,
	tags: { string }?,
	setup: (() -> ())?,
	teardown: (() -> ())?,
	beforeSample: (() -> ...unknown)?,
	afterSample: ((state: unknown, sampler: Sampler) -> ())?,
	heap: Heap?,
	judge: ((view: Judgment) -> string?)?,
}

export type Collection = {
	name: string,
	yardstick: Yardstick,
	benchmarks: { Spec },
	clock: Clock?,
	calibrationAttempts: number?,
}

export type InvalidReason =
	"environment_mismatch"
	| "baseline_mismatch"
	| "unstable"
	| "yardstick_unstable"
	| "yardstick_drift"
	| "heap_unsupported"
	| "deadline_exceeded"

export type Invalid = { reason: InvalidReason, detail: string }

export type Comparison = {
	metric: Metric,
	observed: number,
	baseline: number,
	limit: number,
	regressed: boolean,
	normalized: boolean,
	floored: boolean,
}

export type PhaseResult = {
	name: string,
	measurement: string,
	samples: { number },
	summary: Performance.Summary,
	spread: number?,
	invalid: { Invalid },
	comparison: Comparison?,
	judgment: string?,
	series: Performance.Series,
}

export type Result = {
	attempts: number,
	name: string,
	unit: Unit,
	samples: { number },
	phases: { PhaseResult },
	series: Performance.Series,
	warmupRuns: number,
	iterations: number,
	yardstickBefore: { number },
	yardstickAfter: { number },
	summary: Performance.Summary,
	spread: number?,
	invalid: { Invalid },
	comparison: Comparison?,
	heap: HeapReading?,
	judgment: string?,
	failure: string?,
	elapsedSeconds: number,
}

export type CollectionAttempt = {
	name: string,
	results: { Result },
	yardstickBefore: { number },
	yardstickAfter: { number },
	invalid: { Invalid },
	failure: string?,
}

export type CollectionResult = CollectionAttempt & { attempts: { CollectionAttempt }? }

local scale: { [Unit]: number } = { seconds = 1, milliseconds = 1e3, microseconds = 1e6 }

return { SCALE = table.freeze(scale) }
