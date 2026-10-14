--!strict

local AgentEval = require "../src/agent-eval"
local Fakes = require "./agent-eval-fakes"
local Lute = require "../src/lute"
local Verify = require "../src/core"

type Object = { [string]: unknown }

local PNG = "\137PNG\r\n\26\n" .. "pixels"

local function verdict(choice: string, overall: string?): string
	local criteria: Object = {}
	for _, criterion in AgentEval.judge.DEFAULT_RUBRIC.criteria do
		criteria[criterion.id] = choice
	end
	return Fakes.json {
		criteria = criteria,
		overall = overall or choice,
		confidence = 0.8,
		reasons = { "the spacing is even" },
	}
end

local function comparison(aImages: { string }, bImages: { string }): AgentEval.JudgeComparison
	local function sideOf(
		arm: string,
		paths: { string }
	): { arm: string, run: string, images: { { label: string, path: string } } }
		local images: { { label: string, path: string } } = {}
		for index, path in paths do
			table.insert(images, { label = ("screen-%d"):format(index), path = path })
		end
		return { arm = arm, run = arm .. "-run", images = images }
	end
	return {
		id = "task/agent/seed-1/phone/treatment~baseline",
		task = "task",
		agent = "agent",
		seed = 1,
		device = "phone",
		deviceText = "phone, 844x390 pixels at scale 1, touch",
		brief = "Build a shop.",
		a = sideOf("treatment", aImages),
		b = sideOf("baseline", bImages),
	}
end

local function imagesOf(request: AgentEval.JudgeRequest): { string }
	local list: { string } = {}
	for _, part in request.parts do
		if part.image ~= nil then
			table.insert(list, part.image :: string)
		end
	end
	return list
end

local function firstPath(request: AgentEval.JudgeRequest): string
	return imagesOf(request)[1]
end

return function(suite: Verify.Harness)
	suite:suite("agent evaluation judge", function()
		suite:case("encodes base64 and hashes deterministically", function(context)
			local base64 = AgentEval.base64
			context:expect(base64.encode ""):toBe ""
			context:expect(base64.encode "f"):toBe "Zg=="
			context:expect(base64.encode "fo"):toBe "Zm8="
			context:expect(base64.encode "foo"):toBe "Zm9v"
			context:expect(base64.encode "foobar"):toBe "Zm9vYmFy"
			local bytes: { string } = {}
			for value = 0, 255 do
				table.insert(bytes, string.char(value))
			end
			local all = table.concat(bytes)
			context:expect(base64.decode(base64.encode(all))):toBe(all)
			context:expect(base64.decode "Zm9v!"):toBe(nil)
			context:expect(base64.decode "Zg=a"):toBe(nil)
			context:expect(AgentEval.random.hash "a"):toBe(0xe40c292c)
			context:expect(AgentEval.random.hash "foobar"):toBe(0xbf9cf968)
			local first = AgentEval.random.generator(42)
			local second = AgentEval.random.generator(42)
			for _ = 1, 50 do
				local value = first.integer(1, 6)
				context:expect(value):toBe(second.integer(1, 6))
				context:expect(value >= 1 and value <= 6):toBe(true)
			end
		end)

		suite:case("accepts only a strict verdict object", function(context)
			local rubric = AgentEval.judge.DEFAULT_RUBRIC
			local parsed = AgentEval.judge.parseVerdict(verdict "first", rubric, Lute.parse)
			context:expect(parsed ~= nil and parsed.overall == "first"):toBe(true)
			local fenced = AgentEval.judge.parseVerdict("```json\n" .. verdict "tie" .. "\n```", rubric, Lute.parse)
			context:expect(fenced ~= nil and fenced.overall == "tie"):toBe(true)
			local function problem(text: string): string
				local value, reason = AgentEval.judge.parseVerdict(text, rubric, Lute.parse)
				context:expect(value):toBe(nil)
				return reason :: string
			end
			context:expect(problem("Here it is: " .. verdict "first")):toContain "exactly one JSON object"
			local raw = Lute.parse(verdict "first") :: Object
			local criteria = raw.criteria :: Object
			criteria.polish = nil
			context:expect(problem(Fakes.json(raw))):toContain "verdict.criteria.polish"
			criteria.polish = "left"
			context:expect(problem(Fakes.json(raw))):toContain "first, second or tie"
			criteria.polish = "first"
			raw.extra = 1
			context:expect(problem(Fakes.json(raw))):toContain 'unknown field "extra"'
			raw.extra = nil
			raw.confidence = 2
			context:expect(problem(Fakes.json(raw))):toContain "at most 1"
			raw.confidence = 0.5
			raw.reasons = {}
			context:expect(problem(Fakes.json(raw))):toContain "1 to 10 reasons"
		end)

		suite:case("cancels position bias by judging both orders", function(context)
			local calls = 0
			local biased: AgentEval.JudgeTransport = function(_request)
				calls += 1
				return { text = verdict "first", error = nil, model = "judge" }
			end
			local judged = AgentEval.judge.compare(comparison({ "/a.png" }, { "/b.png" }), {
				transport = biased,
				decode = Lute.parse,
				seed = 3,
			})
			context:expect(calls):toBe(2)
			context:expect(judged.status):toBe "judged"
			context:expect(judged.scoreA):toBe(0.5)
			context:expect(judged.winner):toBe "tie"
			context:expect(judged.consistent):toBe(false)
			context:expect(judged.presentations[1].first ~= judged.presentations[2].first):toBe(true)
			context:expect(judged.presentations[1].model):toBe "judge"

			local preferring: AgentEval.JudgeTransport = function(request)
				local choice = if firstPath(request) == "/b.png" then "first" else "second"
				return { text = verdict(choice), error = nil, model = nil }
			end
			local consistent = AgentEval.judge.compare(comparison({ "/a.png" }, { "/b.png" }), {
				transport = preferring,
				decode = Lute.parse,
				seed = 3,
			})
			context:expect(consistent.winner):toBe "baseline"
			context:expect(consistent.scoreA):toBe(0)
			context:expect(consistent.consistent):toBe(true)
			context:expect(consistent.criteria.hierarchy):toBe(0)
			local again = AgentEval.judge.compare(comparison({ "/a.png" }, { "/b.png" }), {
				transport = preferring,
				decode = Lute.parse,
				seed = 3,
			})
			context:expect(again.order):toBe(consistent.order)
			local orders: { [string]: boolean } = {}
			for seed = 1, 20 do
				orders[AgentEval.judge.compare(comparison({ "/a.png" }, { "/b.png" }), {
					transport = preferring,
					decode = Lute.parse,
					seed = seed,
				}).order] =
					true
			end
			context:expect(orders["a-first"] and orders["b-first"]):toBe(true)
		end)

		suite:case("retries an invalid verdict and keeps a partial judgment explicit", function(context)
			local count = 0
			local flaky: AgentEval.JudgeTransport = function(_request)
				count += 1
				if count == 1 then
					return { text = "I prefer the first one.", error = nil, model = nil }
				end
				if count >= 3 then
					return { text = nil, error = "HTTP 529: overloaded", model = nil }
				end
				return { text = verdict "first", error = nil, model = nil }
			end
			local judged = AgentEval.judge.compare(comparison({ "/a.png" }, { "/b.png" }), {
				transport = flaky,
				decode = Lute.parse,
				seed = 1,
				attempts = 2,
			})
			context:expect(judged.status):toBe "judged"
			context:expect(judged.presentations[1].attempts):toBe(2)
			context:expect(judged.presentations[1].verdict ~= nil):toBe(true)
			context:expect(judged.presentations[2].verdict):toBe(nil)
			context:expect(judged.presentations[2].error):toBe "HTTP 529: overloaded"
			context:expect(judged.consistent):toBe(nil)
			context:expect(judged.detail):toContain "position bias is not controlled"
			local broken = AgentEval.judge.compare(comparison({ "/a.png" }, { "/b.png" }), {
				transport = function(_request)
					error("socket closed", 0)
				end,
				decode = Lute.parse,
				seed = 1,
			})
			context:expect(broken.status):toBe "failed"
			context:expect(broken.presentations[1].error):toBe "socket closed"
		end)

		suite:case("awards a forfeit when one side has no screenshots", function(context)
			local never: AgentEval.JudgeTransport = function(_request)
				error("the judge must not run", 0)
			end
			local forfeit = AgentEval.judge.compare(comparison({ "/a.png" }, {}), {
				transport = never,
				decode = Lute.parse,
				seed = 1,
			})
			context:expect(forfeit.status):toBe "forfeit"
			context:expect(forfeit.winner):toBe "treatment"
			context:expect(forfeit.scoreA):toBe(1)
			local empty = AgentEval.judge.compare(comparison({}, {}), {
				transport = never,
				decode = Lute.parse,
				seed = 1,
			})
			context:expect(empty.status):toBe "skipped"
			context:expect(empty.winner):toBe(nil)
			context:expect(empty.scoreA):toBe(nil)
		end)

		suite:case("sends base64 images to the Messages API and reads the text reply", function(context)
			local sent: { AgentEval.HttpRequest } = {}
			local reply: AgentEval.HttpResponse = {
				status = 200,
				body = Fakes.json {
					model = "claude-opus-5-5",
					stop_reason = "end_turn",
					content = { { type = "text", text = verdict "second" } },
				},
			}
			local transport = AgentEval.judge.anthropic {
				request = function(request: AgentEval.HttpRequest): (AgentEval.HttpResponse?, string?)
					table.insert(sent, request)
					return reply, nil
				end,
				apiKey = "test-key",
				read = function(path: string): string
					if path == "/not-image.txt" then
						return "plain text"
					end
					return PNG
				end,
				encode = Lute.encode,
				decode = Lute.parse,
				effort = "high",
			}
			local request: AgentEval.JudgeRequest =
				{ system = "system text", parts = { { text = "look" }, { image = "/a.png" } } }
			local answer = transport(request)
			context:expect(answer.text):toBe(verdict "second")
			context:expect(answer.model):toBe "claude-opus-5-5"
			context:expect(sent[1].url):toBe "https://api.anthropic.com/v1/messages"
			context:expect(sent[1].method):toBe "POST"
			context:expect(sent[1].headers["x-api-key"]):toBe "test-key"
			context:expect(sent[1].headers["anthropic-version"]):toBe "2023-06-01"
			local body = Lute.parse(sent[1].body :: string) :: Object
			context:expect(body.model):toBe "claude-opus-5-5"
			context:expect(body.max_tokens):toBe(16000)
			context:expect(body.system):toBe "system text"
			context:expect(body.output_config):toEqual { effort = "high" }
			local messages = body.messages :: { Object }
			local content = messages[1].content :: { Object }
			context:expect(content[1]):toEqual { type = "text", text = "look" }
			context:expect(content[2]):toEqual {
				type = "image",
				source = { type = "base64", media_type = "image/png", data = AgentEval.base64.encode(PNG) },
			}
			reply = {
				status = 400,
				body = Fakes.json { error = { type = "invalid_request_error", message = "bad image" } },
			}
			context:expect(transport(request).error):toBe "HTTP 400: bad image"
			reply = { status = 200, body = Fakes.json { model = "m", stop_reason = "refusal", content = {} } }
			context:expect(transport(request).error):toBe "the model refused the request"
			local before = #sent
			local refused = transport { system = "s", parts = { { image = "/not-image.txt" } } }
			context:expect(refused.error):toContain "is not a PNG"
			context:expect(#sent):toBe(before)
		end)

		suite:case("hands neutral image copies to the Claude Code command", function(context)
			local memory = Fakes.memory()
			memory.files.makeDirectory "/runs/treatment"
			memory.files.write("/runs/treatment/main.png", PNG)
			local seen: { AgentEval.Command } = {}
			local transport = AgentEval.judge.claudeCli {
				execute = function(command: AgentEval.Command): AgentEval.Execution
					table.insert(seen, command)
					return {
						started = true,
						exitcode = 0,
						timedOut = false,
						unsupported = false,
						stdout = Fakes.json { type = "result", is_error = false, result = verdict "tie" },
						stderr = "",
						lines = {},
						seconds = 1,
						detail = nil,
					}
				end,
				files = memory.files,
				directory = "/judge",
				decode = Lute.parse,
			}
			local answer = transport {
				system = "system text",
				parts = { { text = "look" }, { image = "/runs/treatment/main.png" } },
			}
			context:expect(answer.text):toBe(verdict "tie")
			context:expect(memory.files.read "/judge/request-1/image-01.png"):toBe(PNG)
			local prompt = memory.files.read "/judge/request-1/prompt.md"
			context:expect(prompt):toContain "./image-01.png"
			context:expect((string.find(prompt, "treatment", 1, true))):toBe(nil)
			context:expect(seen[1].cwd):toBe "/judge/request-1"
			context:expect(seen[1].input):toBe "/judge/request-1/prompt.md"
			context:expect(table.find(seen[1].argv, "--tools") ~= nil):toBe(true)
			context:expect(seen[1].argv[table.find(seen[1].argv, "--tools") :: number + 1]):toBe "Read"
			context:expect(seen[1].argv[table.find(seen[1].argv, "--model") :: number + 1]):toBe "claude-opus-5-5"
		end)

		suite:case("measures agreement with human labels as percent and Cohen's kappa", function(context)
			local humans = { "a", "a", "a", "a", "b", "b", "b", "tie", "tie", "a" }
			local judges = { "a", "a", "a", "b", "b", "b", "a", "tie", "a", "a" }
			local judgments: { AgentEval.Judgment } = {}
			local labels: { AgentEval.Label } = {}
			for index = 1, #humans do
				table.insert(judgments, {
					id = "c" .. index,
					task = "t",
					agent = "g",
					seed = 1,
					device = "d",
					a = "a",
					b = "b",
					status = "judged",
					order = "a-first",
					presentations = {},
					scoreA = 0.5,
					criteria = {},
					winner = judges[index],
					consistent = true,
					detail = nil,
				})
				table.insert(labels, { comparison = "c" .. index, winner = humans[index] })
			end
			table.insert(labels, { comparison = "missing", winner = "a" })
			local decoded = AgentEval.judge.decodeLabels(Lute.parse(Fakes.json { schemaVersion = 1, labels = labels }))
			local calibration = AgentEval.judge.calibrate(judgments, decoded)
			context:expect(calibration.compared):toBe(10)
			context:expect(calibration.agreement):toBeCloseTo(0.7)
			context:expect(calibration.kappa):toBeCloseTo(0.29 / 0.59)
			context:expect(calibration.unjudged):toEqual { "missing" }
			context:expect(calibration.confusion.a.b):toBe(1)
			context:expect(calibration.categories):toEqual { "a", "b", "tie" }
			context
				:expect(function()
					AgentEval.judge.decodeLabels(Lute.parse(Fakes.json {
						schemaVersion = 1,
						labels = { { comparison = "x", winner = "a" }, { comparison = "x", winner = "b" } },
					}))
				end)
				:toThrow "repeats"
		end)
	end)
end
