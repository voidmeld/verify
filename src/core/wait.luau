--!strict

export type Ops = { now: () -> number, sleep: (number) -> (), cancelled: (() -> boolean)? }
export type Spec = {
	name: string,
	deadlineSeconds: number,
	pollSeconds: number,
	probe: (number) -> (boolean, unknown, string?),
	describe: ((unknown) -> string)?,
}
type Reason = "satisfied" | "timeout" | "cancelled" | "refused" | "probe_threw"
export type Result = {
	ok: boolean,
	reason: Reason,
	name: string,
	waitedSeconds: number,
	polls: number,
	observed: unknown,
	detail: string?,
}

local function waitUntil(spec: Spec, ops: Ops): Result
	assert(spec.name ~= "" and spec.deadlineSeconds >= 0 and spec.pollSeconds > 0, "invalid wait bounds")
	local began, polls = ops.now(), 0
	local observed: unknown = nil
	local function finish(reason: Reason, detail: string?): Result
		return {
			ok = reason == "satisfied",
			reason = reason,
			name = spec.name,
			waitedSeconds = ops.now() - began,
			polls = polls,
			observed = observed,
			detail = detail,
		}
	end
	local function timeout(): Result
		local detail = if spec.describe
			then spec.describe(observed)
			else if observed == nil then "nothing" else tostring(observed)
		return finish(
			"timeout",
			("%s: timed out after %.1fs (%d polls); last observed: %s"):format(
				spec.name,
				ops.now() - began,
				polls,
				detail
			)
		)
	end
	while true do
		if ops.cancelled and ops.cancelled() then
			return finish("cancelled", spec.name .. ": cancelled")
		end
		local remaining = spec.deadlineSeconds - (ops.now() - began)
		if remaining <= 0 and polls > 0 then
			return timeout()
		end
		polls += 1
		local called, done, seen, refusal = pcall(spec.probe, math.max(remaining, 0))
		if not called then
			return finish("probe_threw", spec.name .. ": probe failed: " .. tostring(done))
		end
		observed = seen
		if refusal ~= nil then
			return finish("refused", spec.name .. ": " .. refusal)
		end
		if done then
			return finish("satisfied", nil)
		end
		local left = spec.deadlineSeconds - (ops.now() - began)
		if left <= 0 then
			return timeout()
		end
		ops.sleep(math.min(spec.pollSeconds, left))
	end
end

local function awaitValue<T>(predicate: () -> T?, seconds: number, poll: number, ops: Ops, truthy: boolean?): T?
	local observed: T? = nil
	local result = waitUntil({
		name = "value",
		deadlineSeconds = seconds,
		pollSeconds = poll,
		probe = function(): (boolean, unknown, string?)
			local value = predicate()
			observed = value
			return if truthy then not not value else value ~= nil, value, nil
		end,
	}, ops)
	if result.ok then
		return observed
	end
	if result.reason ~= "timeout" and result.reason ~= "cancelled" then
		error(result.detail, 2)
	end
	return nil
end

return { waitUntil = waitUntil, awaitValue = awaitValue }
