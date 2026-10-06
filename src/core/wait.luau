--!strict

export type Ops = {
	now: () -> number,
	sleep: (seconds: number) -> (),
	cancelled: (() -> boolean)?,
}

export type Probe = (remainingSeconds: number) -> (boolean, unknown, string?)

export type Spec = {
	name: string,
	deadlineSeconds: number,
	pollSeconds: number,
	probe: Probe,
	describe: ((observed: unknown) -> string)?,
}

export type Reason = "satisfied" | "timeout" | "cancelled" | "refused" | "probe_threw"

export type Result = {
	ok: boolean,
	reason: Reason,
	name: string,
	waitedSeconds: number,
	polls: number,
	observed: unknown,
	detail: string?,
}

local function describe(spec: Spec, observed: unknown): string
	if spec.describe ~= nil then
		return (spec.describe :: (unknown) -> string)(observed)
	end
	return if observed == nil then "nothing" else tostring(observed)
end

local function waitUntil(spec: Spec, ops: Ops): Result
	assert(type(spec.name) == "string" and spec.name ~= "", "wait name must not be empty")
	assert(spec.deadlineSeconds >= 0, "wait deadline must not be negative")
	assert(spec.pollSeconds > 0, "wait poll interval must be positive")
	local began = ops.now()
	local polls = 0
	local observed: unknown = nil
	local function finish(ok: boolean, reason: Reason, detail: string?): Result
		return {
			ok = ok,
			reason = reason,
			name = spec.name,
			waitedSeconds = ops.now() - began,
			polls = polls,
			observed = observed,
			detail = detail,
		}
	end
	while true do
		if ops.cancelled ~= nil and (ops.cancelled :: () -> boolean)() then
			return finish(
				false,
				"cancelled",
				("%s: cancelled; last observed: %s"):format(spec.name, describe(spec, observed))
			)
		end
		local remaining = spec.deadlineSeconds - (ops.now() - began)
		if remaining <= 0 and polls > 0 then
			return finish(
				false,
				"timeout",
				("%s: timed out after %.1fs (%d polls); last observed: %s"):format(
					spec.name,
					ops.now() - began,
					polls,
					describe(spec, observed)
				)
			)
		end
		polls += 1
		local called, done, seen, refusal = pcall(spec.probe, math.max(remaining, 0))
		if not called then
			return finish(false, "probe_threw", ("%s: probe failed: %s"):format(spec.name, tostring(done)))
		end
		observed = seen
		if refusal ~= nil then
			return finish(false, "refused", ("%s: %s"):format(spec.name, refusal))
		end
		if done then
			return finish(true, "satisfied", nil)
		end
		local left = spec.deadlineSeconds - (ops.now() - began)
		if left <= 0 then
			return finish(
				false,
				"timeout",
				("%s: timed out after %.1fs (%d polls); last observed: %s"):format(
					spec.name,
					ops.now() - began,
					polls,
					describe(spec, observed)
				)
			)
		end
		ops.sleep(math.min(spec.pollSeconds, left))
	end
end

return {
	waitUntil = waitUntil,
}
