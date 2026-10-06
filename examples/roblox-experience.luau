--!strict

local Verify = require "../src/core"
local Experience = require "../src/core/operations"
local RobloxHost = require "../src/roblox/experience-host"
local Types = require "../src/core/types"

export type VisibilityTarget = { Visible: boolean }
export type Options = {
	actor: string,
	actors: { [string]: RobloxHost.Context },
	target: VisibilityTarget,
	transport: RobloxHost.Transport?,
	capture: ((actor: string, checkpoint: string) -> { Types.Artifact })?,
	judge: ((Experience.JudgmentRequest) -> Experience.Judgment)?,
}

local function boolean(value: unknown): boolean
	assert(type(value) == "boolean", "expected boolean")
	return value
end
local function nothing(value: unknown): nil
	assert(value == nil, "expected no value")
	return nil
end
local setVisible = Verify.operation { kind = "action", name = "set-visible", input = boolean, output = nothing }
local visible = Verify.operation { kind = "query", name = "visible", input = nothing, output = boolean }

local function registry(target: VisibilityTarget): RobloxHost.Registry
	return {
		actions = {
			["set-visible"] = RobloxHost.endpoint(function(value: unknown): boolean
				assert(type(value) == "boolean", "set-visible requires a boolean")
				return value
			end, function(value: boolean): unknown
				target.Visible = value
				return nil
			end),
		},
		queries = {
			visible = RobloxHost.endpoint(function(value: unknown): nil
				assert(value == nil, "visible takes no payload")
				return nil
			end, function(): unknown
				return target.Visible
			end),
		},
	}
end

local function case(actor: string, capture: boolean, review: boolean): Verify.NamedCase
	return {
		id = "visibility",
		name = "a native visibility change is observable",
		requires = { "action:set-visible", "query:visible" },
		timeoutSeconds = 5,
		run = function(context: Verify.Context)
			local initial = context:perform(actor, visible, nil)
			assert(type(initial) == "boolean", "visibility must be a boolean")
			context:defer(function()
				context:perform(actor, setVisible, initial)
			end)
			context:perform(actor, setVisible, not initial)
			context:expect(context:perform(actor, visible, nil)):toBe(not initial)
			if capture then
				context:checkpoint(actor, "changed-visibility")
				if review then
					context:judge(actor, "changed-visibility", "the intended native target changed visibility")
				end
			end
		end,
	}
end

local function run(options: Options): Verify.Report
	local host = RobloxHost.create {
		engine = RobloxHost.nativeEngine(),
		actor = options.actor,
		actors = options.actors,
		registry = registry(options.target),
		transport = options.transport,
		capture = options.capture,
		judge = options.judge,
	}
	return Verify.runCase(case(options.actor, options.capture ~= nil, options.judge ~= nil), host)
end

return { run = run, case = case, registry = registry }
