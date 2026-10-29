--!strict

local Base64 = require "../codec/base64"
local Codex = require "./codex"
local Media = require "../codec/image"
local Paths = require "../core/path"
local Random = require "../core/random"
local Schema = require "./schema"
local Services = require "./services"

export type Image = { label: string, path: string }

export type Side = { arm: string, run: string, images: { Image } }

export type Comparison = {
	id: string,
	task: string,
	agent: string,
	seed: number,
	device: string,
	deviceText: string,
	brief: string,
	a: Side,
	b: Side,
}

export type Criterion = { id: string, description: string }

export type Rubric = { criteria: { Criterion }, instructions: string? }

export type Choice = "first" | "second" | "tie"

export type Verdict = {
	criteria: { [string]: Choice },
	overall: Choice,
	confidence: number,
	reasons: { string },
}

export type Part = { text: string?, image: string? }

export type Request = { system: string, parts: { Part }, criteria: { string }? }

export type Reply = { text: string?, error: string?, model: string? }

export type Transport = (request: Request) -> Reply

export type Presentation = {
	first: "a" | "b",
	attempts: number,
	model: string?,
	raw: string?,
	verdict: Verdict?,
	error: string?,
}

export type Judgment = {
	id: string,
	task: string,
	agent: string,
	seed: number,
	device: string,
	a: string,
	b: string,
	status: "judged" | "forfeit" | "skipped" | "failed",
	order: "a-first" | "b-first",
	presentations: { Presentation },
	scoreA: number?,
	criteria: { [string]: number },
	winner: string?,
	consistent: boolean?,
	detail: string?,
}

export type CompareOptions = {
	transport: Transport,
	decode: (text: string) -> unknown,
	rubric: Rubric?,
	seed: number,
	attempts: number?,
}

export type AnthropicOptions = {
	request: (request: Services.HttpRequest) -> (Services.HttpResponse?, string?),
	apiKey: string,
	read: (path: string) -> string,
	encode: (value: unknown) -> string,
	decode: (text: string) -> unknown,
	model: string?,
	maxTokens: number?,
	effort: string?,
	url: string?,
	deadlineSeconds: number?,
	maxImageBytes: number?,
}

export type CliOptions = {
	execute: (command: Services.Command) -> Services.Execution,
	files: Services.Files,
	directory: string,
	decode: (text: string) -> unknown,
	model: string?,
	command: { string }?,
	deadlineSeconds: number?,
}

export type CodexCliOptions = CliOptions & { encode: (value: unknown) -> string, effort: string? }

export type Label = { comparison: string, winner: string }

export type Calibration = {
	compared: number,
	agreement: number?,
	kappa: number?,
	categories: { string },
	confusion: { [string]: { [string]: number } },
	unlabeled: { string },
	unjudged: { string },
}

local DEFAULT_MODEL = "claude-opus-5-5"
local DEFAULT_CODEX_MODEL = "gpt-6.1-sol"
local DEFAULT_CODEX_EFFORT = "medium"
local API_URL = "https://api.anthropic.com/v1/messages"
local API_VERSION = "2023-06-01"
local MAX_IMAGE_BYTES = 5 * 1024 * 1024

local DEFAULT_RUBRIC: Rubric = {
	criteria = {
		{
			id = "hierarchy",
			description = "Visual hierarchy: the most important content and actions stand out, and grouping and order guide the eye.",
		},
		{
			id = "clarity",
			description = "Clarity: text, icons, values and states are easy to read and to understand.",
		},
		{
			id = "consistency",
			description = "Consistency: spacing, alignment, type sizes, colors and component styles follow one system.",
		},
		{
			id = "polish",
			description = "Polish: no clipped, overlapping, misaligned, placeholder or broken elements.",
		},
		{
			id = "fitness",
			description = "Fitness for the task: the interface supports the player task in the brief completely and directly.",
		},
		{
			id = "device_fit",
			description = "Device fit: layout, target sizes and text sizes suit the stated screen and input.",
		},
	},
}

local function checkedString(value: unknown): string
	assert(type(value) == "string")
	return value
end

local function choice(value: unknown, label: string): Choice
	if value == "first" or value == "second" or value == "tie" then
		return value
	end
	return Schema.fail(label, "must be first, second or tie")
end

local function stripFence(text: string): string
	local trimmed = string.match(text, "^%s*(.-)%s*$") or text
	local body = string.match(trimmed, "^```[%w]*%s*\n(.-)\n%s*```$")
	if body ~= nil then
		return body
	end
	return trimmed
end

local function parseVerdict(text: string, rubric: Rubric, decode: (text: string) -> unknown): (Verdict?, string?)
	local ok, result = pcall(function(): Verdict
		local body = stripFence(text)
		if string.sub(body, 1, 1) ~= "{" or string.sub(body, -1) ~= "}" then
			Schema.fail("verdict", "must be exactly one JSON object")
		end
		local decoded, value = pcall(decode, body)
		if not decoded then
			Schema.fail("verdict", "is not valid JSON")
		end
		local raw = Schema.record(value, "verdict")
		Schema.only(raw, "verdict", { "criteria", "overall", "confidence", "reasons" })
		local criteriaRaw = Schema.record(raw.criteria, "verdict.criteria")
		local ids: { string } = {}
		for _, criterion in rubric.criteria do
			table.insert(ids, criterion.id)
		end
		Schema.only(criteriaRaw, "verdict.criteria", ids)
		local criteria: { [string]: Choice } = {}
		for _, id in ids do
			criteria[id] = choice(criteriaRaw[id], "verdict.criteria." .. id)
		end
		local confidence = Schema.number(raw.confidence, "verdict.confidence", 0)
		if confidence > 1 then
			Schema.fail("verdict.confidence", "must be at most 1")
		end
		local reasons = Schema.texts(raw.reasons, "verdict.reasons")
		if #reasons == 0 or #reasons > 10 then
			Schema.fail("verdict.reasons", "must hold 1 to 10 reasons")
		end
		return {
			criteria = criteria,
			overall = choice(raw.overall, "verdict.overall"),
			confidence = confidence,
			reasons = reasons,
		}
	end)
	if ok then
		return result, nil
	end
	return nil, tostring(result)
end

local function system(rubric: Rubric): string
	local lines: { string } = {
		"You are an expert reviewer of game user interfaces.",
		"You compare two interfaces that two different builders made for the same task and the same device.",
		"You do not know who made either interface. Judge only what the images show.",
		"Do not prefer an interface because of its position in the request.",
		"Reply with only one JSON object. Do not write prose or a code fence.",
	}
	if rubric.instructions ~= nil then
		table.insert(lines, rubric.instructions)
	end
	return table.concat(lines, "\n")
end

local function format(rubric: Rubric): string
	local fields: { string } = {}
	for _, criterion in rubric.criteria do
		table.insert(fields, ('"%s": "first" | "second" | "tie"'):format(criterion.id))
	end
	return ('{"criteria": {%s}, "overall": "first" | "second" | "tie", "confidence": <number from 0 to 1>, "reasons": [<1 to 5 short strings>]}'):format(
		table.concat(fields, ", ")
	)
end

local function request(comparison: Comparison, first: Side, second: Side, rubric: Rubric): Request
	local parts: { Part } = {}
	local criteria: { string } = {}
	for _, criterion in rubric.criteria do
		table.insert(criteria, ("- %s: %s"):format(criterion.id, criterion.description))
	end
	table.insert(parts, {
		text = table.concat({
			"Task brief:",
			comparison.brief,
			"",
			"Device: " .. comparison.deviceText,
			"",
			"Criteria:",
			table.concat(criteria, "\n"),
		}, "\n"),
	})
	for index, side in { first, second } do
		local name = if index == 1 then "first" else "second"
		if #side.images == 0 then
			table.insert(parts, { text = ("The %s interface has no screenshots."):format(name) })
		end
		for _, image in side.images do
			table.insert(parts, { text = ("The %s interface, screen %q:"):format(name, image.label) })
			table.insert(parts, { image = image.path })
		end
	end
	table.insert(parts, {
		text = "Compare the first and the second interface on each criterion and overall. Reply with this JSON shape: "
			.. format(rubric),
	})
	local ids: { string } = {}
	for _, criterion in rubric.criteria do
		table.insert(ids, criterion.id)
	end
	return { system = system(rubric), parts = parts, criteria = ids }
end

local function score(presentation: Presentation, value: Choice): number
	if value == "tie" then
		return 0.5
	end
	local firstWins = value == "first"
	local aFirst = presentation.first == "a"
	return if firstWins == aFirst then 1 else 0
end

local function compare(comparison: Comparison, options: CompareOptions): Judgment
	local rubric = options.rubric or DEFAULT_RUBRIC
	local generator = Random.generator(Random.derive(options.seed, comparison.id))
	local aFirst = generator.next() < 0.5
	local judgment: Judgment = {
		id = comparison.id,
		task = comparison.task,
		agent = comparison.agent,
		seed = comparison.seed,
		device = comparison.device,
		a = comparison.a.arm,
		b = comparison.b.arm,
		status = "failed",
		order = if aFirst then "a-first" else "b-first",
		presentations = {},
		criteria = {},
	}
	local aEmpty = #comparison.a.images == 0
	local bEmpty = #comparison.b.images == 0
	if aEmpty or bEmpty then
		if aEmpty and bEmpty then
			judgment.status = "skipped"
			judgment.detail = "neither run produced screenshots"
			return judgment
		end
		judgment.status = "forfeit"
		local scoreA = if aEmpty then 0 else 1
		judgment.scoreA = scoreA
		judgment.winner = if aEmpty then comparison.b.arm else comparison.a.arm
		judgment.detail = ("%s produced no screenshots"):format(if aEmpty then comparison.a.arm else comparison.b.arm)
		for _, criterion in rubric.criteria do
			judgment.criteria[criterion.id] = scoreA
		end
		return judgment
	end
	local attempts = options.attempts or 2
	local orders: { "a" | "b" } = if aFirst then { "a", "b" } else { "b", "a" }
	for _, firstSide in orders do
		local presentation: Presentation = {
			first = if firstSide == "a" then "a" else "b",
			attempts = 0,
		}
		local first = if firstSide == "a" then comparison.a else comparison.b
		local second = if firstSide == "a" then comparison.b else comparison.a
		local built = request(comparison, first, second, rubric)
		for _ = 1, attempts do
			presentation.attempts += 1
			local called, reply = pcall(options.transport, built)
			if not called then
				presentation.error = tostring(reply)
				continue
			end
			local answer = reply
			presentation.model = answer.model or presentation.model
			if answer.text == nil then
				presentation.error = answer.error or "the judge returned no text"
				continue
			end
			presentation.raw = answer.text
			local verdict, problem = parseVerdict(answer.text, rubric, options.decode)
			if verdict ~= nil then
				presentation.verdict = verdict
				presentation.error = nil
				break
			end
			presentation.error = problem
		end
		table.insert(judgment.presentations, presentation)
	end
	local scores: { number } = {}
	local criteria: { [string]: { number } } = {}
	for _, presentation in judgment.presentations do
		local verdict = presentation.verdict
		if verdict ~= nil then
			table.insert(scores, score(presentation, verdict.overall))
			for _, criterion in rubric.criteria do
				local list = criteria[criterion.id] or {}
				table.insert(list, score(presentation, verdict.criteria[criterion.id]))
				criteria[criterion.id] = list
			end
		end
	end
	if #scores == 0 then
		judgment.detail = "no presentation returned a valid verdict"
		return judgment
	end
	local sum = 0
	for _, value in scores do
		sum += value
	end
	judgment.status = "judged"
	local scoreA = sum / #scores
	judgment.scoreA = scoreA
	for id, list in criteria do
		local total = 0
		for _, value in list do
			total += value
		end
		judgment.criteria[id] = total / #list
	end
	judgment.winner = if scoreA > 0.5 then comparison.a.arm elseif scoreA < 0.5 then comparison.b.arm else "tie"
	if #scores == 2 then
		judgment.consistent = scores[1] == scores[2]
	else
		judgment.detail = "one presentation failed, so position bias is not controlled"
	end
	return judgment
end

local function field(value: unknown, key: string): unknown
	if type(value) ~= "table" then
		return nil
	end
	return (value :: { [string]: unknown })[key]
end

local function anthropic(options: AnthropicOptions): Transport
	assert(type(options.apiKey) == "string" and options.apiKey ~= "", "the Messages transport needs an API key")
	local model = options.model or DEFAULT_MODEL
	local limit = options.maxImageBytes or MAX_IMAGE_BYTES
	return function(input: Request): Reply
		local content: { { [string]: unknown } } = {}
		for _, part in input.parts do
			if part.text ~= nil then
				local block: { [string]: unknown } = { type = "text", text = part.text }
				table.insert(content, block)
			elseif part.image ~= nil then
				local bytes = options.read(part.image)
				local kind = Media.mediaType(bytes)
				if kind == nil then
					return {
						error = ("%s is not a PNG, JPEG, GIF or WebP image"):format(part.image),
					}
				end
				if #bytes > limit then
					return {
						error = ("%s has %d bytes, above the limit of %d"):format(part.image, #bytes, limit),
					}
				end
				local block: { [string]: unknown } = {
					type = "image",
					source = { type = "base64", media_type = kind, data = Base64.encode(bytes) },
				}
				table.insert(content, block)
			end
		end
		local body: { [string]: unknown } = {
			model = model,
			max_tokens = options.maxTokens or 16000,
			system = input.system,
			messages = { { role = "user", content = content } },
		}
		if options.effort ~= nil then
			body.output_config = { effort = options.effort }
		end
		local response, problem = options.request {
			url = options.url or API_URL,
			method = "POST",
			headers = {
				["content-type"] = "application/json",
				["x-api-key"] = options.apiKey,
				["anthropic-version"] = API_VERSION,
			},
			body = options.encode(body),
			deadlineSeconds = options.deadlineSeconds or 300,
		}
		if response == nil then
			return { text = nil, error = problem or "the request was not answered", model = nil }
		end
		local answer = response
		local decoded, value = pcall(options.decode, answer.body)
		if answer.status ~= 200 then
			local message = if decoded then field(field(value, "error"), "message") else nil
			return {
				error = ("HTTP %d: %s"):format(
					answer.status,
					if type(message) == "string" then message else string.sub(answer.body, 1, 300)
				),
			}
		end
		if not decoded then
			return { text = nil, error = "the response is not JSON", model = nil }
		end
		local served = field(value, "model")
		local servedModel = if type(served) == "string" then served else nil
		if field(value, "stop_reason") == "refusal" then
			return { text = nil, error = "the model refused the request", model = servedModel }
		end
		local texts: { string } = {}
		local blocks = field(value, "content")
		if type(blocks) == "table" then
			for _, block in ipairs(blocks :: { unknown }) do
				if field(block, "type") == "text" and type(field(block, "text")) == "string" then
					table.insert(texts, checkedString(field(block, "text")))
				end
			end
		end
		if #texts == 0 then
			return { text = nil, error = "the response has no text block", model = servedModel }
		end
		return { text = table.concat(texts, "\n"), error = nil, model = servedModel }
	end
end

local function cliInput(options: CliOptions, input: Request, sequence: number): (string, string, { string })
	local directory = Paths.join(options.directory, ("request-%d"):format(sequence))
	if options.files.exists(directory) then
		options.files.remove(directory)
	end
	options.files.makeDirectory(directory)
	local lines: { string } = {}
	local images: { string } = {}
	for _, part in input.parts do
		if part.text ~= nil then
			table.insert(lines, part.text)
		elseif part.image ~= nil then
			local extension = string.match(part.image, "(%.[%w]+)$") or ".png"
			local name = ("image-%02d%s"):format(#images + 1, string.lower(extension))
			options.files.copy(part.image, Paths.join(directory, name))
			table.insert(images, "./" .. name)
			table.insert(lines, ("Read the image file ./%s."):format(name))
		end
	end
	local promptFile = Paths.join(directory, "prompt.md")
	options.files.write(promptFile, table.concat(lines, "\n\n"))
	return directory, promptFile, images
end

local function claudeCli(options: CliOptions): Transport
	local sequence = 0
	return function(input: Request): Reply
		sequence += 1
		local directory, promptFile = cliInput(options, input, sequence)
		local argv: { string } = table.clone(options.command or { "claude" })
		for _, word in
			{
				"-p",
				"--output-format",
				"json",
				"--model",
				options.model or DEFAULT_MODEL,
				"--tools",
				"Read",
				"--permission-mode",
				"bypassPermissions",
				"--strict-mcp-config",
				"--no-session-persistence",
				"--append-system-prompt",
				input.system,
			}
		do
			table.insert(argv, word)
		end
		local execution = options.execute {
			argv = argv,
			cwd = directory,
			input = promptFile,
			deadlineSeconds = options.deadlineSeconds or 600,
			stamp = false,
			scratch = directory,
		}
		if not execution.started then
			return { text = nil, error = execution.detail or "the judge command did not start", model = nil }
		end
		if execution.timedOut then
			return { text = nil, error = "the judge command timed out", model = nil }
		end
		local decoded, value = pcall(options.decode, execution.stdout)
		if not decoded then
			return {
				error = ("the judge command printed no JSON (exit %d): %s"):format(
					execution.exitcode,
					string.sub(execution.stderr, 1, 300)
				),
			}
		end
		if field(value, "is_error") == true then
			local message = field(value, "result")
			return {
				error = "the judge command failed: " .. (if type(message) == "string" then message else "no detail"),
			}
		end
		local result = field(value, "result")
		if type(result) ~= "string" then
			return { text = nil, error = "the judge command returned no result text", model = nil }
		end
		return { text = result, error = nil, model = options.model or DEFAULT_MODEL }
	end
end

local function codexCli(options: CodexCliOptions): Transport
	local sequence = 0
	local model = options.model or DEFAULT_CODEX_MODEL
	local effort = options.effort or DEFAULT_CODEX_EFFORT
	return function(input: Request): Reply
		sequence += 1
		local directory, promptFile, images = cliInput(options, input, sequence)
		local ids: { string } = input.criteria or {}
		if input.criteria == nil then
			for _, criterion in DEFAULT_RUBRIC.criteria do
				table.insert(ids, criterion.id)
			end
		end
		local choiceSchema = { type = "string", enum = { "first", "second", "tie" } }
		local properties: { [string]: unknown } = {}
		for _, id in ids do
			properties[id] = choiceSchema
		end
		local schema = {
			type = "object",
			additionalProperties = false,
			required = { "criteria", "overall", "confidence", "reasons" },
			properties = {
				criteria = { type = "object", additionalProperties = false, properties = properties, required = ids },
				overall = choiceSchema,
				confidence = { type = "number", minimum = 0, maximum = 1 },
				reasons = { type = "array", minItems = 1, maxItems = 5, items = { type = "string" } },
			},
		}
		options.files.write(Paths.join(directory, "schema.json"), options.encode(schema))
		local extra =
			{ "--ignore-user-config", "--output-schema", "./schema.json", "--output-last-message", "./answer.json" }
		for _, image in images do
			table.insert(extra, "--image")
			table.insert(extra, image)
		end
		local argv = Codex.arguments({
			workspace = directory,
			model = model,
			instructions = input.system
				.. "\nUse only the attached images and the prompt. Do not use tools or inspect other files.",
			options = { command = options.command, effort = effort, sandbox = "read-only", arguments = extra },
		}, nil, options.decode)
		local execution = options.execute {
			argv = argv,
			cwd = directory,
			input = promptFile,
			deadlineSeconds = options.deadlineSeconds or 600,
			stamp = true,
			scratch = directory,
		}
		local events: { string } = {}
		for _, line in execution.lines do
			table.insert(events, line.text)
		end
		options.files.write(
			Paths.join(directory, "events.jsonl"),
			if #events > 0 then table.concat(events, "\n") .. "\n" else execution.stdout
		)
		options.files.write(Paths.join(directory, "stderr.txt"), execution.stderr)
		if not execution.started then
			return { error = execution.detail or "the judge command did not start", model = model }
		end
		if execution.timedOut then
			return { error = "the judge command timed out", model = model }
		end
		if execution.exitcode ~= 0 then
			return {
				error = ("the judge command failed (exit %d): %s"):format(
					execution.exitcode,
					string.sub(execution.stderr, 1, 300)
				),
				model = model,
			}
		end
		local lines: { Services.Line } = if #execution.lines > 0
			then execution.lines
			else Services.lines(execution.stdout)
		local transcript = Codex.parse(lines, options.decode)
		local otherItem = false
		for _, line in lines do
			local decoded, event = pcall(options.decode, line.text)
			local kind = if decoded then field(event, "type") else nil
			if kind == "item.started" or kind == "item.updated" or kind == "item.completed" then
				local itemKind = field(field(event, "item"), "type")
				if itemKind ~= "agent_message" and itemKind ~= "reasoning" and itemKind ~= "error" then
					otherItem = true
				end
			end
		end
		if transcript.toolCalls > 0 or otherItem then
			return { error = "the judge command used tools; the blind presentation is invalid", model = model }
		end
		if transcript.status ~= "success" or transcript.malformed > 0 then
			return { error = "the judge command did not complete a turn", model = model }
		end
		local answer = Paths.join(directory, "answer.json")
		if not options.files.exists(answer) then
			return { error = "the judge command returned no result text", model = model }
		end
		return { text = options.files.read(answer), model = model }
	end
end

local function decodeLabels(value: unknown): { Label }
	local raw = Schema.record(value, "labels")
	Schema.only(raw, "labels", { "schemaVersion", "labels" })
	if raw.schemaVersion ~= 1 then
		Schema.fail("labels.schemaVersion", "must be 1")
	end
	local result: { Label } = {}
	local seen: { [string]: boolean } = {}
	for index, item in Schema.list(raw.labels, "labels.labels") do
		local where = ("labels.labels[%d]"):format(index)
		local entry = Schema.record(item, where)
		Schema.only(entry, where, { "comparison", "winner", "labeler", "note" })
		local label: Label = {
			comparison = Schema.text(entry.comparison, where .. ".comparison"),
			winner = Schema.text(entry.winner, where .. ".winner"),
		}
		if seen[label.comparison] then
			Schema.fail(where .. ".comparison", ("repeats %q"):format(label.comparison))
		end
		seen[label.comparison] = true
		table.insert(result, label)
	end
	return result
end

local function calibrate(judgments: { Judgment }, labels: { Label }): Calibration
	local byId: { [string]: Judgment } = {}
	for _, judgment in judgments do
		if judgment.status == "judged" and judgment.winner ~= nil then
			byId[judgment.id] = judgment
		end
	end
	local labeled: { [string]: boolean } = {}
	local pairs: { { human: string, judge: string } } = {}
	local calibration: Calibration = {
		compared = 0,
		categories = {},
		confusion = {},
		unlabeled = {},
		unjudged = {},
	}
	for _, label in labels do
		labeled[label.comparison] = true
		local judgment = byId[label.comparison]
		if judgment == nil then
			table.insert(calibration.unjudged, label.comparison)
		else
			table.insert(pairs, { human = label.winner, judge = checkedString(judgment.winner) })
		end
	end
	for _, judgment in judgments do
		if judgment.status == "judged" and not labeled[judgment.id] then
			table.insert(calibration.unlabeled, judgment.id)
		end
	end
	table.sort(calibration.unlabeled)
	table.sort(calibration.unjudged)
	calibration.compared = #pairs
	if #pairs == 0 then
		return calibration
	end
	local categorySet: { [string]: boolean } = {}
	local agreed = 0
	local humanCounts: { [string]: number } = {}
	local judgeCounts: { [string]: number } = {}
	for _, pair in pairs do
		categorySet[pair.human] = true
		categorySet[pair.judge] = true
		if pair.human == pair.judge then
			agreed += 1
		end
		humanCounts[pair.human] = (humanCounts[pair.human] or 0) + 1
		judgeCounts[pair.judge] = (judgeCounts[pair.judge] or 0) + 1
		local row = calibration.confusion[pair.human] or {}
		row[pair.judge] = (row[pair.judge] or 0) + 1
		calibration.confusion[pair.human] = row
	end
	calibration.categories = Schema.sortedKeys(categorySet)
	local observed = agreed / #pairs
	local expected = 0
	for _, category in calibration.categories do
		expected += ((humanCounts[category] or 0) / #pairs) * ((judgeCounts[category] or 0) / #pairs)
	end
	calibration.agreement = observed
	if expected < 1 then
		calibration.kappa = (observed - expected) / (1 - expected)
	end
	return calibration
end

local function decodeRubric(value: unknown, label: string): Rubric?
	if Schema.absent(value) then
		return nil
	end
	local raw = Schema.record(value, label)
	Schema.only(raw, label, { "instructions", "criteria" })
	local entries = Schema.list(raw.criteria, label .. ".criteria")
	if #entries == 0 then
		return Schema.fail(label .. ".criteria", "must hold at least one criterion")
	end
	local criteria: { Criterion } = {}
	local ids: { string } = {}
	for index, entry in entries do
		local itemLabel = ("%s.criteria[%d]"):format(label, index)
		local item = Schema.record(entry, itemLabel)
		Schema.only(item, itemLabel, { "id", "description" })
		local id = Schema.identifier(item.id, itemLabel .. ".id")
		table.insert(ids, id)
		table.insert(criteria, { id = id, description = Schema.text(item.description, itemLabel .. ".description") })
	end
	Schema.unique(ids, label .. ".criteria")
	return { criteria = criteria, instructions = Schema.optionalText(raw.instructions, label .. ".instructions") }
end

return {
	DEFAULT_MODEL = DEFAULT_MODEL,
	decodeRubric = decodeRubric,
	DEFAULT_CODEX_MODEL = DEFAULT_CODEX_MODEL,
	DEFAULT_CODEX_EFFORT = DEFAULT_CODEX_EFFORT,
	DEFAULT_RUBRIC = DEFAULT_RUBRIC,
	parseVerdict = parseVerdict,
	request = request,
	compare = compare,
	anthropic = anthropic,
	claudeCli = claudeCli,
	codexCli = codexCli,
	decodeLabels = decodeLabels,
	calibrate = calibrate,
}
