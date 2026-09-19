# Execution contract

A plan is a finite set of units, declared capabilities and policy. Verify executes that plan;
a consumer decides what each locator means and supplies the authorized host.

`Core.validatePlan(draft)` normalizes ids, locators, groups, tags, requirements, weights and policy.
Duplicate ids/locators and malformed fields fail. `selectPlan` narrows by ids, tags, capabilities,
groups or a predicate over the same source-bearing subject used by harness/session selection.
`partitionPlan(plan, count, mode?)` assigns every unit once and keeps fixture groups whole.
Count and weighted batching are deterministic functions of authored metadata. `planDigest` binds
meaning, not timing. `caseId` composes stable ids. `planFromManifest` accepts an explicitly validated
manifest; `validateManifest` remains the input boundary. All selection and partitioning use the plan.
Discovery and changed-file reachability belong to consumers, not a second scheduler in Verify.

## Host boundary

`Core.execute(plan, host, options?)` drives capability negotiation, fixture setup/cleanup, batching,
run deadlines, failure accounting and receipt composition. A host supplies `runBatch`; optional
parallel dispatch and artifact routing preserve the same report semantics. A batch outcome is
`completed`, `faulted`, `timed_out`, or `cancelled`; only a completed valid report carries verdicts.
The host must stop timed-out/cancelled work and account for every dispatched batch. A clean exit
without the expected receipt is a fault.

`execute` derives completeness from the original plan. Narrowing, missing results, infrastructure
faults and contradictory retries remain explicit facts. A narrowed pass is not the complete gate.
Retries apply only to declared infrastructure outcomes. Every attempt is retained; ordinary
assertion failures are never retried into green. Fixture and cleanup failures remain independently
visible. Artifact sinks return references, not proof of durability or authenticity.

The typed `Host`, `BatchOutcome`, `ExecutionOptions`, `PlanPolicy` and returned `ExecutionReport`
are exported by `src/core`. [Behavioral tests](../tests/execution.spec.luau) exercise dropped,
reordered, duplicate, forged and disagreeing deliveries using the injected fake host.

## Lute workers

`Lute.host({worker, command?, directory, capabilities?, ...})` starts one process per batch.
`Lute.pool({worker, command?, directory, size, recycleAfter?, ...})` bounds persistent workers;
close the pool even if execution raises. The pool owns unique mailboxes and readiness/sentinel
protocol. Poisoned, absent, unresponsive and exhausted workers return named faults. Consumer output
files remain the consumer's isolation responsibility.

`worker`/`poolWorker` load a registration function returned by each module.
`selfRegisteringWorker`/`selfRegisteringPoolWorker` instead call `load(locator, harness)`, so an
existing BDD surface can register against each unit's private harness. Both run through the same
session, failure classifier and mailbox lifecycle. No global registry is created on import.
[One-shot](../examples/self-registering-worker.luau) and
[pooled](../examples/self-registering-pool-worker.luau) entries show the caller seam.

`runWorkerBatch` and `runSelfRegisteringWorkerBatch` expose that lifecycle for injected execution.
An explicit `classifyLoadFailure` may name a recognized prerequisite as skipped/unsupported;
unrecognized or throwing classifiers leave a hard failure. Successful loading followed by broken
registration is a failure. Every missing source remains a named case.

Pool reuse can retain module-local state. `recycleAfter` bounds reuse but cannot make stateful
consumer modules isolated. Real tests in `tests/pool.spec.luau` check cold/warm verdict equivalence,
process failures and namespace ownership; they establish no production performance claim.

`Lute.corpus` supplies injected discovery rules, require-affinity grouping, literal subset matching,
worker bounds and stable lock text. A query matching nothing selects nothing. The consumer owns
filesystem discovery and the committed complete corpus; dynamic edges cannot be inferred from a
static require scan. `encodeBatch`/`decodeBatch` transport the existing plan-batch schema.

## Engine and external execution

Mount the portable core/BDD and needed Roblox adapters, create a source-bound session or harness,
then transport its report. Engine manifests, live services, driver startup, publication identity,
credentials, scheduling, image capture and durable storage are consumer operations. Verify's
injected observation/capture/tier adapters judge those supplied facts; they do not authenticate a
remote service or authorize an external action.

Use tagged log transport or bounded segments from [the API](api.md#reports-and-transport). Enumerate
all expected responses. Refuse missing, mixed, conflicting and stale evidence before release
acceptance. A saved old report proves no current source, environment, screenshot or runtime result.
