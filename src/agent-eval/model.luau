--!strict

local Paths = require "../codec/path"
local Schema = require "./schema"
local Services = require "./services"

export type Budgets = {
	maxTurns: number?,
	maxOutputTokens: number?,
	maxCostUsd: number?,
	wallSeconds: number,
}

export type Rect = { x: number, y: number, width: number, height: number }

export type Device = {
	id: string,
	width: number,
	height: number,
	scale: number,
	input: { string },
	safeArea: Rect?,
}

export type ArmSetup = {
	studio: { place: string, build: { string }, keep: boolean? }?,
	overlay: { string },
	instructions: { string },
	mcp: string?,
	allowedTools: { string }?,
	disallowedTools: { string }?,
	env: { [string]: string },
}

export type CheckKind = "command" | "verify" | "audit"

export type ReportExpectation = { cases: { string }?, minimum: number?, exact: boolean? }

export type Check = {
	id: string,
	kind: CheckKind,
	argv: { string },
	required: boolean,
	after: { string },
	deadlineSeconds: number?,
	env: { [string]: string },
	perDevice: boolean,
	scores: boolean,
	dump: string?,
	audit: { [string]: unknown },
	report: ReportExpectation?,
}

export type Task = {
	id: string,
	title: string,
	tier: string,
	directory: string,
	brief: string,
	briefText: string,
	starter: string?,
	from: string?,
	arms: { [string]: ArmSetup },
	checks: { Check },
	devices: { Device },
	budgets: Budgets,
	digest: string,
}

export type Arm = { id: string, setup: ArmSetup }

export type Agent = {
	id: string,
	adapter: string,
	model: string?,
	options: { [string]: unknown },
}

export type Suite = {
	id: string,
	directory: string,
	tasks: { Task },
	arms: { Arm },
	agents: { Agent },
	seeds: { number },
	parallelism: number,
	evidence: string?,
	judge: { [string]: unknown },
}

export type RunSpec = {
	id: string,
	path: string,
	task: Task,
	arm: Arm,
	agent: Agent,
	seed: number,
	order: number,
	parent: string?,
	digest: string,
}

export type Loader = {
	files: Services.Files,
	hash: (bytes: string) -> string,
	decodeJson: (text: string) -> unknown,
}

local SCHEMA_VERSION = 1
local CHECK_KINDS: { [string]: CheckKind } = { command = "command", verify = "verify", audit = "audit" }

local function version(value: Schema.Record, label: string)
	local declared = Schema.number(value.schemaVersion, label .. ".schemaVersion", 1, true)
	if declared ~= SCHEMA_VERSION then
		Schema.fail(label .. ".schemaVersion", ("must be %d"):format(SCHEMA_VERSION))
	end
end

local function rect(value: unknown, label: string): Rect?
	if Schema.absent(value) then
		return nil
	end
	local raw = Schema.record(value, label)
	Schema.only(raw, label, { "x", "y", "width", "height" })
	return {
		x = Schema.number(raw.x, label .. ".x"),
		y = Schema.number(raw.y, label .. ".y"),
		width = Schema.number(raw.width, label .. ".width", 0),
		height = Schema.number(raw.height, label .. ".height", 0),
	}
end

local function devices(value: unknown, label: string): { Device }
	local result: { Device } = {}
	for index, item in Schema.list(value, label) do
		local where = ("%s[%d]"):format(label, index)
		local raw = Schema.record(item, where)
		Schema.only(raw, where, { "id", "width", "height", "scale", "input", "safeArea" })
		table.insert(result, {
			id = Schema.identifier(raw.id, where .. ".id"),
			width = Schema.number(raw.width, where .. ".width", 1, true),
			height = Schema.number(raw.height, where .. ".height", 1, true),
			scale = Schema.optionalNumber(raw.scale, where .. ".scale", 0) or 1,
			input = Schema.texts(raw.input, where .. ".input"),
			safeArea = rect(raw.safeArea, where .. ".safeArea"),
		})
	end
	local ids: { string } = {}
	for _, device in result do
		table.insert(ids, device.id)
	end
	Schema.unique(ids, label)
	return result
end

local function budgets(value: unknown, label: string, base: Budgets?): Budgets
	local raw: Schema.Record = if Schema.absent(value) then {} else Schema.record(value, label)
	Schema.only(raw, label, { "maxTurns", "maxOutputTokens", "maxCostUsd", "wallSeconds" })
	local inherited: Budgets = base or { wallSeconds = 1800 }
	return {
		maxTurns = Schema.optionalNumber(raw.maxTurns, label .. ".maxTurns", 1, true) or inherited.maxTurns,
		maxOutputTokens = Schema.optionalNumber(raw.maxOutputTokens, label .. ".maxOutputTokens", 1, true)
			or inherited.maxOutputTokens,
		maxCostUsd = Schema.optionalNumber(raw.maxCostUsd, label .. ".maxCostUsd", 0) or inherited.maxCostUsd,
		wallSeconds = Schema.optionalNumber(raw.wallSeconds, label .. ".wallSeconds", 1) or inherited.wallSeconds,
	}
end

local function armSetup(value: unknown, label: string, directory: string, files: Services.Files): ArmSetup
	local raw: Schema.Record = if Schema.absent(value) then {} else Schema.record(value, label)
	Schema.only(
		raw,
		label,
		{ "id", "overlay", "instructions", "mcp", "studio", "allowedTools", "disallowedTools", "env" }
	)
	local studio: { place: string, build: { string }, keep: boolean? }? = nil
	if not Schema.absent(raw.studio) then
		local config = Schema.record(raw.studio, label .. ".studio")
		Schema.only(config, label .. ".studio", { "place", "build", "keep" })
		studio = {
			place = Schema.text(config.place, label .. ".studio.place"),
			build = Schema.texts(config.build, label .. ".studio.build"),
			keep = Schema.flag(config.keep, label .. ".studio.keep", false),
		}
	end
	local overlay: { string } = {}
	for index, path in Schema.texts(raw.overlay, label .. ".overlay") do
		local resolved = Paths.join(directory, path)
		if not files.exists(resolved) then
			Schema.fail(("%s.overlay[%d]"):format(label, index), ("names a missing path %s"):format(resolved))
		end
		table.insert(overlay, resolved)
	end
	local instructions: { string } = {}
	local declared = Schema.optionalText(raw.instructions, label .. ".instructions")
	if declared ~= nil then
		local resolved = Paths.join(directory, declared)
		if not files.exists(resolved) then
			Schema.fail(label .. ".instructions", ("names a missing file %s"):format(resolved))
		end
		table.insert(instructions, files.read(resolved))
	end
	local mcp: string? = nil
	local declaredMcp = Schema.optionalText(raw.mcp, label .. ".mcp")
	if declaredMcp ~= nil then
		mcp = Paths.join(directory, declaredMcp)
		if not files.exists(mcp :: string) then
			Schema.fail(label .. ".mcp", ("names a missing file %s"):format(mcp :: string))
		end
	end
	return {
		overlay = overlay,
		studio = studio,
		instructions = instructions,
		mcp = mcp,
		allowedTools = Schema.optionalTexts(raw.allowedTools, label .. ".allowedTools"),
		disallowedTools = Schema.optionalTexts(raw.disallowedTools, label .. ".disallowedTools"),
		env = Schema.dictionary(raw.env, label .. ".env"),
	}
end

local function merge(base: ArmSetup, extra: ArmSetup?): ArmSetup
	if extra == nil then
		return base
	end
	local overlay = table.clone(base.overlay)
	for _, path in extra.overlay do
		table.insert(overlay, path)
	end
	local instructions = table.clone(base.instructions)
	for _, text in extra.instructions do
		table.insert(instructions, text)
	end
	local env = table.clone(base.env)
	for key, value in extra.env do
		env[key] = value
	end
	return {
		overlay = overlay,
		instructions = instructions,
		mcp = extra.mcp or base.mcp,
		studio = extra.studio or base.studio,
		allowedTools = extra.allowedTools or base.allowedTools,
		disallowedTools = extra.disallowedTools or base.disallowedTools,
		env = env,
	}
end

local function report(value: unknown, label: string): ReportExpectation?
	if Schema.absent(value) then
		return nil
	end
	local raw = Schema.record(value, label)
	Schema.only(raw, label, { "cases", "minimum", "exact" })
	return {
		cases = Schema.optionalTexts(raw.cases, label .. ".cases"),
		minimum = Schema.optionalNumber(raw.minimum, label .. ".minimum", 0, true),
		exact = if Schema.absent(raw.exact) then nil else Schema.flag(raw.exact, label .. ".exact", false),
	}
end

local function checks(value: unknown, label: string): { Check }
	local result: { Check } = {}
	local ids: { string } = {}
	for index, item in Schema.list(value, label) do
		local where = ("%s[%d]"):format(label, index)
		local raw = Schema.record(item, where)
		Schema.only(raw, where, {
			"id",
			"kind",
			"argv",
			"required",
			"after",
			"deadlineSeconds",
			"env",
			"perDevice",
			"scores",
			"dump",
			"audit",
			"report",
		})
		local kindName = Schema.text(raw.kind, where .. ".kind")
		local kind = CHECK_KINDS[kindName]
		if kind == nil then
			Schema.fail(where .. ".kind", "must be command, verify or audit")
		end
		local argv = Schema.texts(raw.argv, where .. ".argv")
		local dump = Schema.optionalText(raw.dump, where .. ".dump")
		if kind == "audit" then
			if dump == nil then
				Schema.fail(where .. ".dump", "is required for an audit check")
			end
			if #argv > 0 then
				Schema.fail(where .. ".argv", "is not used by an audit check")
			end
		elseif #argv == 0 then
			Schema.fail(where .. ".argv", "must name a command")
		end
		if kind == "verify" and table.find(argv, "{report}") == nil then
			local mentioned = false
			for _, word in argv do
				if string.find(word, "{report}", 1, true) ~= nil then
					mentioned = true
				end
			end
			if not mentioned then
				Schema.fail(where .. ".argv", "must pass {report} to a verify check")
			end
		end
		local audit = if Schema.absent(raw.audit) then {} else Schema.record(raw.audit, where .. ".audit")
		local check: Check = {
			id = Schema.identifier(raw.id, where .. ".id"),
			kind = kind :: CheckKind,
			argv = argv,
			required = Schema.flag(raw.required, where .. ".required", true),
			after = Schema.texts(raw.after, where .. ".after"),
			deadlineSeconds = Schema.optionalNumber(raw.deadlineSeconds, where .. ".deadlineSeconds", 1),
			env = Schema.dictionary(raw.env, where .. ".env"),
			perDevice = Schema.flag(raw.perDevice, where .. ".perDevice", false),
			scores = Schema.flag(raw.scores, where .. ".scores", false),
			dump = dump,
			audit = audit,
			report = report(raw.report, where .. ".report"),
		}
		if check.kind == "verify" and check.report == nil then
			check.report = { cases = nil, minimum = 1, exact = nil }
		end
		table.insert(ids, check.id)
		table.insert(result, check)
	end
	Schema.unique(ids, label)
	local known: { [string]: Check } = {}
	for _, check in result do
		for _, dependency in check.after do
			if known[dependency] == nil then
				Schema.fail(
					("%s.%s.after"):format(label, check.id),
					("names %q, which is not an earlier check"):format(dependency)
				)
			end
			if known[dependency].kind == "audit" and check.kind ~= "audit" then
				Schema.fail(("%s.%s.after"):format(label, check.id), "cannot run a command after an audit check")
			end
		end
		known[check.id] = check
	end
	return result
end

local function manifest(files: Services.Files, hash: (string) -> string, root: string): string
	local entries: { string } = {}
	local function walk(directory: string, prefix: string)
		local listed = files.list(directory)
		table.sort(listed, function(left, right)
			return left.name < right.name
		end)
		for _, entry in listed do
			local path = Paths.join(directory, entry.name)
			local relative = if prefix == "" then entry.name else prefix .. "/" .. entry.name
			if entry.kind == "directory" then
				walk(path, relative)
			else
				table.insert(entries, relative .. ":" .. hash(files.read(path)))
			end
		end
	end
	if files.isDirectory(root) then
		walk(root, "")
	else
		table.insert(entries, Paths.leaf(root) .. ":" .. hash(files.read(root)))
	end
	return table.concat(entries, "\n")
end

local function decodeTask(
	value: unknown,
	directory: string,
	defaults: { budgets: Budgets, devices: { Device }, arms: { [string]: boolean } },
	loader: Loader
): Task
	local files = loader.files
	local raw = Schema.record(value, "task")
	local label = "task " .. tostring(raw.id)
	Schema.only(
		raw,
		label,
		{ "schemaVersion", "id", "title", "tier", "brief", "starter", "from", "arms", "checks", "devices", "budgets" }
	)
	version(raw, label)
	local id = Schema.identifier(raw.id, label .. ".id")
	local brief = Paths.join(directory, Schema.text(raw.brief, label .. ".brief"))
	if not files.exists(brief) then
		Schema.fail(label .. ".brief", ("names a missing file %s"):format(brief))
	end
	local starterName = Schema.optionalText(raw.starter, label .. ".starter")
	local from = if Schema.absent(raw.from) then nil else Schema.identifier(raw.from, label .. ".from")
	if (starterName == nil) == (from == nil) then
		Schema.fail(label, "must declare exactly one of starter or from")
	end
	local starter: string? = nil
	if starterName ~= nil then
		starter = Paths.join(directory, starterName)
		if not files.isDirectory(starter :: string) then
			Schema.fail(label .. ".starter", ("names a missing directory %s"):format(starter :: string))
		end
	end
	local arms: { [string]: ArmSetup } = {}
	if not Schema.absent(raw.arms) then
		for armId, setup in Schema.record(raw.arms, label .. ".arms") do
			if not defaults.arms[armId] then
				Schema.fail(label .. ".arms", ("names an undeclared arm %q"):format(armId))
			end
			arms[armId] = armSetup(setup, ("%s.arms.%s"):format(label, armId), directory, files)
		end
	end
	local declaredDevices = devices(raw.devices, label .. ".devices")
	local task: Task = {
		id = id,
		title = Schema.text(raw.title, label .. ".title"),
		tier = Schema.optionalText(raw.tier, label .. ".tier") or "default",
		directory = directory,
		brief = brief,
		briefText = files.read(brief),
		starter = starter,
		from = from,
		arms = arms,
		checks = checks(raw.checks, label .. ".checks"),
		devices = if #declaredDevices > 0 then declaredDevices else defaults.devices,
		budgets = budgets(raw.budgets, label .. ".budgets", defaults.budgets),
		digest = "",
	}
	local needsDevices = false
	for _, check in task.checks do
		if check.perDevice then
			needsDevices = true
		end
	end
	if needsDevices and #task.devices == 0 then
		Schema.fail(label .. ".checks", "uses perDevice checks but the task has no devices")
	end
	local pieces: { string } = { Schema.canonical(raw), task.briefText }
	if starter ~= nil then
		table.insert(pieces, manifest(files, loader.hash, starter))
	end
	for _, armId in Schema.sortedKeys(arms) do
		for _, path in arms[armId].overlay do
			table.insert(pieces, manifest(files, loader.hash, path))
		end
		for _, text in arms[armId].instructions do
			table.insert(pieces, text)
		end
		if arms[armId].mcp ~= nil then
			table.insert(pieces, files.read(arms[armId].mcp :: string))
		end
	end
	task.digest = loader.hash(table.concat(pieces, "\n\0\n"))
	return task
end

local function order(tasks: { Task }): { Task }
	local byId: { [string]: Task } = {}
	for _, task in tasks do
		if byId[task.id] ~= nil then
			Schema.fail("suite.tasks", ("repeats task %q"):format(task.id))
		end
		byId[task.id] = task
	end
	local result: { Task } = {}
	local state: { [string]: string } = {}
	local function visit(task: Task, trail: { string })
		if state[task.id] == "done" then
			return
		end
		if state[task.id] == "active" then
			Schema.fail("suite.tasks", ("has a follow-up cycle: %s"):format(table.concat(trail, " -> ")))
		end
		state[task.id] = "active"
		if task.from ~= nil then
			local parent = byId[task.from :: string]
			if parent == nil then
				Schema.fail("task " .. task.id .. ".from", ("names an unknown task %q"):format(task.from :: string))
			end
			local next = table.clone(trail)
			table.insert(next, parent.id)
			visit(parent, next)
		end
		state[task.id] = "done"
		table.insert(result, task)
	end
	for _, task in tasks do
		visit(task, { task.id })
	end
	return result
end

local function decodeSuite(value: unknown, path: string, loader: Loader): Suite
	local files = loader.files
	local directory = Paths.parent(path)
	local raw = Schema.record(value, "suite")
	Schema.only(raw, "suite", {
		"schemaVersion",
		"id",
		"tasks",
		"arms",
		"agents",
		"seeds",
		"parallelism",
		"evidence",
		"budgets",
		"devices",
		"judge",
	})
	version(raw, "suite")
	local arms: { Arm } = {}
	local armIds: { [string]: boolean } = {}
	for index, item in Schema.list(raw.arms, "suite.arms") do
		local where = ("suite.arms[%d]"):format(index)
		local record = Schema.record(item, where)
		local id = Schema.identifier(record.id, where .. ".id")
		if armIds[id] then
			Schema.fail("suite.arms", ("repeats arm %q"):format(id))
		end
		armIds[id] = true
		table.insert(arms, { id = id, setup = armSetup(record, where, directory, files) })
	end
	if #arms == 0 then
		Schema.fail("suite.arms", "must declare at least one arm")
	end
	local agents: { Agent } = {}
	local agentIds: { string } = {}
	for index, item in Schema.list(raw.agents, "suite.agents") do
		local where = ("suite.agents[%d]"):format(index)
		local record = Schema.record(item, where)
		Schema.only(record, where, { "id", "adapter", "model", "options" })
		local agent: Agent = {
			id = Schema.identifier(record.id, where .. ".id"),
			adapter = Schema.text(record.adapter, where .. ".adapter"),
			model = Schema.optionalText(record.model, where .. ".model"),
			options = if Schema.absent(record.options) then {} else Schema.record(record.options, where .. ".options"),
		}
		table.insert(agentIds, agent.id)
		table.insert(agents, agent)
	end
	if #agents == 0 then
		Schema.fail("suite.agents", "must declare at least one agent")
	end
	Schema.unique(agentIds, "suite.agents")
	local seeds: { number } = {}
	for index, item in Schema.list(raw.seeds, "suite.seeds") do
		table.insert(seeds, Schema.number(item, ("suite.seeds[%d]"):format(index), 0, true))
	end
	if #seeds == 0 then
		seeds = { 1 }
	end
	local seen: { [number]: boolean } = {}
	for _, seed in seeds do
		if seen[seed] then
			Schema.fail("suite.seeds", ("repeats seed %d"):format(seed))
		end
		seen[seed] = true
	end
	local defaults = {
		budgets = budgets(raw.budgets, "suite.budgets", nil),
		devices = devices(raw.devices, "suite.devices"),
		arms = armIds,
	}
	local tasks: { Task } = {}
	for index, item in Schema.texts(raw.tasks, "suite.tasks") do
		local taskDirectory = Paths.join(directory, item)
		local taskFile = Paths.join(taskDirectory, "task.json")
		if not files.exists(taskFile) then
			Schema.fail(("suite.tasks[%d]"):format(index), ("has no task.json at %s"):format(taskFile))
		end
		local decoded = loader.decodeJson(files.read(taskFile))
		table.insert(tasks, decodeTask(decoded, taskDirectory, defaults, loader))
	end
	if #tasks == 0 then
		Schema.fail("suite.tasks", "must list at least one task directory")
	end
	local evidence = Schema.optionalText(raw.evidence, "suite.evidence")
	return {
		id = Schema.identifier(raw.id, "suite.id"),
		directory = directory,
		tasks = order(tasks),
		arms = arms,
		agents = agents,
		seeds = seeds,
		parallelism = Schema.optionalNumber(raw.parallelism, "suite.parallelism", 1, true) or 1,
		evidence = if evidence ~= nil then Paths.join(directory, evidence) else nil,
		judge = if Schema.absent(raw.judge) then {} else Schema.record(raw.judge, "suite.judge"),
	}
end

export type Selection = {
	tasks: { string }?,
	arms: { string }?,
	agents: { string }?,
	seeds: { number }?,
}

local function runPath(task: string, arm: string, agent: string, seed: number): string
	return ("runs/%s/%s/%s/seed-%d"):format(task, arm, agent, seed)
end

local function armDigest(setup: ArmSetup, loader: Loader): string
	local pieces: { string } = {}
	for _, path in setup.overlay do
		table.insert(pieces, manifest(loader.files, loader.hash, path))
	end
	for _, text in setup.instructions do
		table.insert(pieces, text)
	end
	if setup.mcp ~= nil then
		table.insert(pieces, loader.files.read(setup.mcp))
	end
	table.insert(
		pieces,
		Schema.canonical {
			studio = setup.studio,
			allowedTools = setup.allowedTools,
			disallowedTools = setup.disallowedTools,
			env = setup.env,
		}
	)
	return loader.hash(table.concat(pieces, "\n\0\n"))
end

local function plan(suite: Suite, loader: Loader, selection: Selection?): { RunSpec }
	local chosen: Selection = selection or {}
	local function wanted(list: { string }?, id: string): boolean
		return list == nil or table.find(list, id) ~= nil
	end
	local armDigests: { [string]: string } = {}
	for _, arm in suite.arms do
		armDigests[arm.id] = armDigest(arm.setup, loader)
	end
	local result: { RunSpec } = {}
	local byKey: { [string]: RunSpec } = {}
	local counter = 0
	for seedIndex, seed in suite.seeds do
		if chosen.seeds ~= nil and table.find(chosen.seeds, seed) == nil then
			continue
		end
		for _, task in suite.tasks do
			for _, agent in suite.agents do
				if not wanted(chosen.agents, agent.id) then
					continue
				end
				for offset = 0, #suite.arms - 1 do
					local arm = suite.arms[(offset + seedIndex - 1) % #suite.arms + 1]
					if not wanted(chosen.arms, arm.id) then
						continue
					end
					local key = ("%s/%s/%s/%d"):format(task.id, arm.id, agent.id, seed)
					local parent: RunSpec? = nil
					if task.from ~= nil then
						parent = byKey[("%s/%s/%s/%d"):format(task.from :: string, arm.id, agent.id, seed)]
					end
					local setup = merge(arm.setup, task.arms[arm.id])
					local spec: RunSpec = {
						id = key,
						path = runPath(task.id, arm.id, agent.id, seed),
						task = task,
						arm = { id = arm.id, setup = setup },
						agent = agent,
						seed = seed,
						order = 0,
						parent = if parent ~= nil then parent.id else nil,
						digest = loader.hash(table.concat({
							key,
							task.digest,
							armDigests[arm.id],
							Schema.canonical {
								id = agent.id,
								adapter = agent.adapter,
								model = agent.model,
								options = agent.options,
							},
							tostring(seed),
							if parent ~= nil then parent.digest else "",
						}, "\n")),
					}
					byKey[key] = spec
					if wanted(chosen.tasks, task.id) then
						counter += 1
						spec.order = counter
						table.insert(result, spec)
					end
				end
			end
		end
	end
	return result
end

return {
	SCHEMA_VERSION = SCHEMA_VERSION,
	decodeSuite = decodeSuite,
	plan = plan,
	runPath = runPath,
	merge = merge,
	manifest = manifest,
	devices = devices,
	checks = checks,
}
