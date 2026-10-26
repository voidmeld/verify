--!strict

local Judge = require "./judge"
local Model = require "./model"
local Paths = require "../core/path"
local Result = require "./result"
local Schema = require "./schema"
local Services = require "./services"

export type Options = {
	suite: Model.Suite,
	results: { Result.RunResult },
	transport: Judge.Transport,
	transportName: string,
	files: Services.Files,
	hash: (bytes: string) -> string,
	encode: (value: unknown) -> string,
	decode: (text: string) -> unknown,
	evidence: string,
	seed: number,
	rubric: Judge.Rubric?,
	attempts: number?,
	resume: boolean?,
	log: ((line: string) -> ())?,
}

type Stored = { key: string, judgment: Judge.Judgment }

local BRIEF_LIMIT = 8000

local function deviceText(device: Model.Device): string
	local input = if #device.input > 0 then table.concat(device.input, ", ") else "unspecified input"
	return ("%s, %dx%d pixels at scale %s, %s"):format(
		device.id,
		device.width,
		device.height,
		tostring(device.scale),
		input
	)
end

local function comparisons(suite: Model.Suite, results: { Result.RunResult }): { Judge.Comparison }
	local byKey: { [string]: Result.RunResult } = {}
	for _, result in results do
		byKey[("%s/%s/%s/%d"):format(result.task, result.arm, result.agent, result.seed)] = result
	end
	local list: { Judge.Comparison } = {}
	for _, seed in suite.seeds do
		for _, task in suite.tasks do
			for _, agent in suite.agents do
				for leftIndex = 1, #suite.arms do
					for rightIndex = leftIndex + 1, #suite.arms do
						local left = suite.arms[leftIndex].id
						local right = suite.arms[rightIndex].id
						local a = byKey[("%s/%s/%s/%d"):format(task.id, left, agent.id, seed)]
						local b = byKey[("%s/%s/%s/%d"):format(task.id, right, agent.id, seed)]
						if a == nil or b == nil then
							continue
						end
						for _, device in task.devices do
							local function side(result: Result.RunResult): Judge.Side
								local images: { Judge.Image } = {}
								for _, capture in result.captures do
									if capture.device == device.id then
										table.insert(images, { label = capture.label, path = capture.path })
									end
								end
								table.sort(images, function(x, y)
									return x.label < y.label
								end)
								return { arm = result.arm, run = result.id, images = images }
							end
							table.insert(list, {
								id = ("%s/%s/seed-%d/%s/%s~%s"):format(task.id, agent.id, seed, device.id, left, right),
								task = task.id,
								agent = agent.id,
								seed = seed,
								device = device.id,
								deviceText = deviceText(device),
								brief = string.sub(task.briefText, 1, BRIEF_LIMIT),
								a = side(a),
								b = side(b),
							})
						end
					end
				end
			end
		end
	end
	return list
end

local function decodeJudgment(value: unknown): Judge.Judgment
	local entry = Schema.record(value, "judgment")
	local status = Schema.text(entry.status, "judgment.status")
	if status ~= "judged" and status ~= "forfeit" and status ~= "skipped" and status ~= "failed" then
		Schema.fail("judgment.status", "is not a judgment status")
	end
	local criteria: { [string]: number } = {}
	if not Schema.absent(entry.criteria) then
		for key, value in Schema.record(entry.criteria, "judgment.criteria") do
			criteria[key] = Schema.number(value, "judgment.criteria." .. key)
		end
	end
	local order = Schema.text(entry.order, "judgment.order")
	local presentations: { Judge.Presentation } = {}
	for index, item in Schema.list(entry.presentations, "judgment.presentations") do
		local where = ("judgment.presentations[%d]"):format(index)
		local raw = Schema.record(item, where)
		local verdict: Judge.Verdict? = nil
		if not Schema.absent(raw.verdict) then
			local verdictRaw = Schema.record(raw.verdict, where .. ".verdict")
			local choices: { [string]: Judge.Choice } = {}
			for key, value in Schema.record(verdictRaw.criteria, where .. ".verdict.criteria") do
				if value ~= "first" and value ~= "second" and value ~= "tie" then
					Schema.fail(where .. ".verdict.criteria." .. key, "must be first, second or tie")
				end
				choices[key] = if value == "first" then "first" elseif value == "second" then "second" else "tie"
			end
			local overall = verdictRaw.overall
			if overall ~= "first" and overall ~= "second" and overall ~= "tie" then
				Schema.fail(where .. ".verdict.overall", "must be first, second or tie")
			end
			verdict = {
				criteria = choices,
				overall = if overall == "first" then "first" elseif overall == "second" then "second" else "tie",
				confidence = Schema.number(verdictRaw.confidence, where .. ".verdict.confidence", 0),
				reasons = Schema.texts(verdictRaw.reasons, where .. ".verdict.reasons"),
			}
		end
		table.insert(presentations, {
			first = if raw.first == "b" then "b" else "a",
			attempts = Schema.number(raw.attempts, where .. ".attempts", 0, true),
			model = Schema.optionalText(raw.model, where .. ".model"),
			raw = if type(raw.raw) == "string" then raw.raw else nil,
			verdict = verdict,
			error = if type(raw.error) == "string" then raw.error else nil,
		})
	end
	return {
		id = Schema.text(entry.id, "judgment.id"),
		task = Schema.text(entry.task, "judgment.task"),
		agent = Schema.text(entry.agent, "judgment.agent"),
		seed = Schema.number(entry.seed, "judgment.seed", 0, true),
		device = Schema.text(entry.device, "judgment.device"),
		a = Schema.text(entry.a, "judgment.a"),
		b = Schema.text(entry.b, "judgment.b"),
		status = if status == "judged"
			then "judged"
			elseif status == "forfeit" then "forfeit"
			elseif status == "skipped" then "skipped"
			else "failed",
		order = if order == "b-first" then "b-first" else "a-first",
		presentations = presentations,
		scoreA = Schema.optionalNumber(entry.scoreA, "judgment.scoreA", 0),
		criteria = criteria,
		winner = Schema.optionalText(entry.winner, "judgment.winner"),
		consistent = if type(entry.consistent) == "boolean" then entry.consistent else nil,
		detail = if type(entry.detail) == "string" then entry.detail else nil,
	}
end

local function run(options: Options): { Judge.Judgment }
	local files = options.files
	local rubric = options.rubric or Judge.DEFAULT_RUBRIC
	local log = options.log or function(_line: string) end
	local directory = Paths.join(options.evidence, "judgments")
	files.makeDirectory(directory)
	local captureHash: { [string]: string } = {}
	for _, result in options.results do
		for _, capture in result.captures do
			captureHash[capture.path] = capture.sha256
		end
	end
	local judgments: { Judge.Judgment } = {}
	for _, comparison in comparisons(options.suite, options.results) do
		local pieces: { string } = { comparison.id, options.transportName, Schema.canonical(rubric), comparison.brief }
		for _, side in { comparison.a, comparison.b } do
			for _, image in side.images do
				table.insert(pieces, image.label .. "=" .. (captureHash[image.path] or ""))
			end
		end
		table.insert(pieces, tostring(options.seed))
		local key = options.hash(table.concat(pieces, "\n"))
		local path = Paths.join(directory, key .. ".json")
		local reused: Judge.Judgment? = nil
		if options.resume ~= false and files.exists(path) then
			local ok, stored = pcall(function(): Stored
				local raw = Schema.record(options.decode(files.read(path)), "stored judgment")
				return { key = Schema.text(raw.key, "stored judgment.key"), judgment = decodeJudgment(raw.judgment) }
			end)
			if ok and stored.key == key then
				reused = stored.judgment
			end
		end
		local judgment: Judge.Judgment
		if reused ~= nil then
			judgment = reused
			log(("judge %s: reused (%s)"):format(comparison.id, tostring(judgment.winner)))
		else
			judgment = Judge.compare(comparison, {
				transport = options.transport,
				decode = options.decode,
				rubric = rubric,
				seed = options.seed,
				attempts = options.attempts,
			})
			files.write(path, options.encode { key = key, judgment = judgment })
			log(("judge %s: %s, winner %s"):format(comparison.id, judgment.status, tostring(judgment.winner)))
		end
		table.insert(judgments, judgment)
	end
	files.write(
		Paths.join(options.evidence, "judgments.json"),
		options.encode {
			schemaVersion = 1,
			suite = options.suite.id,
			seed = options.seed,
			transport = options.transportName,
			judgments = judgments,
		}
	)
	return judgments
end

local function load(evidence: string, files: Services.Files, decode: (text: string) -> unknown): { Judge.Judgment }
	local path = Paths.join(evidence, "judgments.json")
	if not files.exists(path) then
		return {}
	end
	local raw = Schema.record(decode(files.read(path)), "judgments")
	local result: { Judge.Judgment } = {}
	for _, item in Schema.list(raw.judgments, "judgments.judgments") do
		table.insert(result, decodeJudgment(item))
	end
	return result
end

return {
	comparisons = comparisons,
	run = run,
	load = load,
}
