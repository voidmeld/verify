--!strict

local fs = require "@std/fs"
local process = require "@std/process"
local json = require "@std/json"
local Eval = require "../src/agent-eval"
local Lute = require "../src/lute"
local Files = require "../src/lute/files"

type Provisioned = { config: string, close: () -> () }
type Studio = { id: string, name: string }
type Call = { name: string, arguments: { [string]: unknown }, refusal: string? }
type Reply = { id: number, result: { content: { { type: string?, text: string? } } }?, error: { message: string }? }

local function info(provisioned: Provisioned): Studio
	local parent = assert(string.match(provisioned.config, "^(.*)/[^/]+$"))
	local scope = Eval.lute.decode(fs.readFileToString(parent .. "/studio-scope.json")) :: { studio: Studio }
	return scope.studio
end

local function exchange(services: Eval.Services, config: string, directory: string, calls: { Call }): { Reply }
	fs.createDirectory(directory, { makeParents = true })
	local settings =
		Eval.lute.decode(fs.readFileToString(config)) :: { mcpServers: { studio: { command: string, args: { string } } } }
	local server = settings.mcpServers.studio
	local argv = { server.command }
	for _, word in server.args do
		table.insert(argv, word)
	end
	local requests: { string } = { json.serialize { jsonrpc = "2.0", id = 1, method = "initialize", params = {} } }
	for index, call in calls do
		table.insert(
			requests,
			json.serialize {
				jsonrpc = "2.0",
				id = index + 1,
				method = "tools/call",
				params = { name = call.name, arguments = call.arguments },
			}
		)
	end
	local input = directory .. "/requests.jsonl"
	fs.writeStringToFile(input, table.concat(requests, "\n") .. "\n")
	local result = services.execute { argv = argv, input = input, deadlineSeconds = 180 }
	fs.writeStringToFile(directory .. "/responses.jsonl", result.stdout)
	assert(result.started and result.exitcode == 0 and not result.timedOut, "scoped proxy failed: " .. result.stderr)
	local responses: { Reply } = {}
	for line in string.gmatch(result.stdout, "[^\r\n]+") do
		local reply = Eval.lute.decode(line) :: Reply
		responses[reply.id] = reply
	end
	assert(#responses == #requests, "scoped proxy lost responses: " .. result.stdout)
	assert(responses[1].error == nil, Eval.lute.encode(responses[1]))
	local replies: { Reply } = {}
	for index, call in calls do
		local reply = responses[index + 1]
		if call.refusal then
			assert(
				reply.error ~= nil and string.find(reply.error.message, call.refusal, 1, true) ~= nil,
				Eval.lute.encode(reply)
			)
		else
			assert(reply.error == nil, Eval.lute.encode(reply))
		end
		table.insert(replies, reply)
	end
	return replies
end

return function()
	local directory = Files.claimDirectory(Files.temporary "verify-native-scope")
	local services = Eval.lute.services()
	local project, place, payload =
		directory .. "/fixture.project.json", directory .. "/fixture.rbxl", directory .. "/payload.luau"
	fs.writeStringToFile(payload, '--!strict\nreturn "left]]>right"\n')
	fs.writeStringToFile(
		project,
		Eval.lute.encode {
			name = "VerifyScope",
			tree = {
				["$className"] = "DataModel",
				Lighting = { ["$properties"] = { Technology = "Future" } },
				ReplicatedStorage = { ["$className"] = "ReplicatedStorage", Payload = { ["$path"] = payload } },
				Workspace = {
					["$className"] = "Workspace",
					Floor = {
						["$className"] = "Part",
						["$properties"] = { Anchored = true, Size = { 100, 1, 100 }, Position = { 0, -1, 0 } },
					},
					Spawn = { ["$className"] = "SpawnLocation", ["$properties"] = { Anchored = true } },
				},
			},
		}
	)
	local cleanup: { () -> () } = {}
	local provision = assert(services.studio, "scoped Studio service missing")
	services.studio = function(workspace, evidence, target, build, seconds): Provisioned
		local opened = provision(workspace, evidence, target, build, seconds)
		local closed = false
		local function close()
			if not closed then
				opened.close()
				closed = true
			end
		end
		table.insert(cleanup, close)
		return { config = opened.config, close = close }
	end
	local ok, problem = pcall(function()
		local built = services.execute { argv = { "rojo", "build", project, "-o", place }, deadlineSeconds = 60 }
		assert(built.exitcode == 0 and not built.timedOut, built.stderr)
		local unrelated, failure =
			Lute.studio.launch { place = place, directory = directory .. "/unrelated", runSeconds = 900 }
		assert(unrelated ~= nil, failure)
		local outside = unrelated
		table.insert(cleanup, function()
			local closed = outside.close()
			assert(#closed.survivors == 0 and closed.session.acknowledged, "unrelated fixture cleanup failed")
		end)
		assert(outside.session.execute("Edit", "game:SetAttribute('ScopeUnrelated', true); return true").ok)
		local function open(label: string): Provisioned
			fs.createDirectory(directory .. "/" .. label, { makeParents = true })
			local target = directory .. "/" .. label .. "/agent.rbxl"
			return assert(services.studio)(
				tostring(process.cwd()),
				directory .. "/" .. label,
				target,
				{ "rojo", "build", project, "-o", target },
				600
			)
		end
		local a, b = open "a", open "b"
		local aInfo, bInfo, cInfo = info(a), info(b), outside.session.studio
		assert(aInfo.id ~= bInfo.id and aInfo.id ~= cInfo.id and bInfo.id ~= cInfo.id, "native Studio IDs alias")
		local function survivor(label: string)
			exchange(services, b.config, directory .. "/peer-" .. label, {
				{
					name = "execute_luau",
					arguments = {
						datamodel_type = "Edit",
						code = "assert(not game:GetAttribute('ScopeCrossed')); return 'peer alive'",
					},
				},
			})
			assert(
				outside.session.execute(
					"Edit",
					"assert(game:GetAttribute('ScopeUnrelated')); assert(not game:GetAttribute('ScopeCrossed')); return true"
				).ok,
				"unrelated Studio was changed or closed"
			)
		end
		for index, own in { a, b } do
			local self = if index == 1 then aInfo else bInfo
			local other = if index == 1 then bInfo else aInfo
			local calls: { Call } = { { name = "list_roblox_studios", arguments = {} } }
			for _, target in { other.id, cInfo.id } do
				for _, name in
					{
						"list_roblox_studios",
						"start_stop_play",
						"screen_capture",
						"execute_luau",
						"get_console_output",
						"input",
					}
				do
					local arguments: { [string]: unknown } = { studio_id = target }
					if name == "execute_luau" or name == "input" then
						arguments.code = "game:SetAttribute('ScopeCrossed', true); return true"
					end
					if name == "execute_luau" then
						arguments.datamodel_type = "Edit"
					end
					if name == "start_stop_play" then
						arguments.is_start = true
					end
					table.insert(calls, { name = name, arguments = arguments, refusal = "targets another Studio" })
				end
			end
			table.insert(calls, { name = "unknown", arguments = {}, refusal = "outside the run scope" })
			table.insert(calls, {
				name = "execute_luau",
				arguments = {
					datamodel_type = "Edit",
					code = "assert(not game:GetAttribute('ScopeCrossed')); assert(require(game.ReplicatedStorage.Payload) == 'left]]>right'); print('verify scoped console'); return 'scoped edit'",
				},
			})
			local captureIndex = #calls + 1
			table.insert(calls, { name = "screen_capture", arguments = {} })
			table.insert(calls, { name = "start_stop_play", arguments = { is_start = true } })
			table.insert(calls, {
				name = "input",
				arguments = {
					code = [[
task.wait(2)
local input = assert(game:GetService('UserInputService'):CreateVirtualInput())
input:SendKey(true, Enum.KeyCode.Space, false)
task.wait(0.1)
input:SendKey(false, Enum.KeyCode.Space, false)
return 'scoped input'
]],
				},
			})
			table.insert(calls, { name = "get_console_output", arguments = {} })
			table.insert(calls, { name = "start_stop_play", arguments = { is_start = false } })
			local replies = exchange(services, own.config, directory .. "/isolation-" .. index, calls)
			local listing = assert(replies[1].result)
			local studios = Eval.lute.decode(assert(listing.content[1].text)) :: { studios: { Studio } }
			assert(#studios.studios == 1 and studios.studios[1].id == self.id, "scope exposes another real Studio")
			local image = false
			for _, content in assert(replies[captureIndex].result).content do
				image = image or content.type == "image"
			end
			assert(image, "scoped capture lost its image")
		end
		local aScope = directory .. "/a/studio-scope.json"
		local originalScope = fs.readFileToString(aScope)
		local limited = Eval.lute.decode(originalScope) :: { [string]: unknown }
		limited.callSeconds = 5
		fs.writeStringToFile(aScope, Eval.lute.encode(limited))
		local afterTimeout = exchange(services, a.config, directory .. "/native-request-timeout", {
			{
				name = "execute_luau",
				arguments = {
					datamodel_type = "Edit",
					code = "game:SetAttribute('ScopeSlowCount', (game:GetAttribute('ScopeSlowCount') or 0) + 1); task.wait(8); return 'slow complete'",
				},
				refusal = "may have been applied",
			},
			{ name = "list_roblox_studios", arguments = {} },
			{
				name = "execute_luau",
				arguments = {
					datamodel_type = "Edit",
					code = "assert(game:GetAttribute('ScopeSlowCount') == 1); return 'observed once'",
				},
			},
		})
		local timeoutListing =
			Eval.lute.decode(assert(assert(afterTimeout[2].result).content[1].text)) :: { studios: { Studio } }
		assert(
			#timeoutListing.studios == 1 and timeoutListing.studios[1].id == aInfo.id,
			"timeout changed the scoped Studio"
		)
		assert(
			assert(afterTimeout[3].result).content[1].text == "observed once",
			"timed-out native command was replayed"
		)
		fs.writeStringToFile(aScope, originalScope)
		a.close()
		assert(not fs.exists(directory .. "/a/studio-scope.json"), "first scope remained after cleanup")
		survivor "first-closed"
		local taskDirectory = directory .. "/task"
		fs.createDirectory(taskDirectory .. "/starter", { makeParents = true })
		fs.writeStringToFile(taskDirectory .. "/brief.md", "Exercise native scoped cleanup.")
		fs.writeStringToFile(
			taskDirectory .. "/task.json",
			Eval.lute.encode {
				schemaVersion = 1,
				id = "cleanup",
				title = "Scoped cleanup",
				brief = "brief.md",
				starter = "starter",
				checks = {
					{
						id = "completed",
						kind = "command",
						argv = {
							tostring(process.execPath()),
							"run",
							Eval.lute.absolute "tests/programs/exit-with.luau",
							"0",
						},
					},
				},
			}
		)
		local suite = Eval.decodeSuite({
			schemaVersion = 1,
			id = "native-scope-cleanup",
			tasks = { "task" },
			seeds = { 1 },
			arms = {
				{
					id = "native",
					studio = {
						place = "{evidence}/agent.rbxl",
						build = { "rojo", "build", project, "-o", "{evidence}/agent.rbxl" },
					},
				},
			},
			agents = { { id = "raise", adapter = "raise" }, { id = "timeout", adapter = "timeout" } },
			budgets = { wallSeconds = 180 },
		}, directory .. "/suite.json", Eval.lute.loader())
		local sleeper = directory .. "/sleep.luau"
		fs.writeStringToFile(sleeper, 'require("@std/task").wait(30)')
		local scopedPaths: { string } = {}
		local function remember(request: Eval.AgentRequest)
			if #scopedPaths > 0 then
				assert(not fs.exists(scopedPaths[#scopedPaths]), "previous adapter scope remained open")
				survivor "raised-adapter-closed"
			end
			table.insert(scopedPaths, request.directory .. "/studio-scope.json")
			assert(fs.exists(scopedPaths[#scopedPaths]), "adapter did not receive a live native scope")
		end
		local summary = Eval.run {
			suite = suite,
			loader = Eval.lute.loader(),
			services = services,
			evidence = directory .. "/cleanup",
			encode = Eval.lute.encode,
			decode = Eval.lute.decode,
			parallelism = 1,
			adapters = {
				raise = {
					id = "raise",
					run = function(request): Eval.AgentOutcome
						remember(request)
						error("native adapter failure", 0)
					end,
				},
				timeout = {
					id = "timeout",
					run = function(request, given): Eval.AgentOutcome
						remember(request)
						local result = given.execute {
							argv = { tostring(process.execPath()), "run", sleeper },
							deadlineSeconds = 0.5,
						}
						assert(result.started and result.timedOut, "native adapter process did not time out")
						return {
							status = "timed_out",
							exitcode = result.exitcode,
							detail = "native adapter timeout",
							transcript = Eval.transcript.parseClaudeStream({}, Eval.lute.decode),
							lines = result.lines,
							stderr = result.stderr,
							seconds = result.seconds,
						}
					end,
				},
			},
		}
		assert(#summary.results == 2 and #scopedPaths == 2, "native cleanup adapters did not run")
		local raised, timedOut = false, false
		for _, result in summary.results do
			assert(not result.passed, "failed native adapter passed")
			raised = raised or string.find(result.detail or "", "native adapter failure", 1, true) ~= nil
			timedOut = timedOut or result.status == "timed_out"
		end
		assert(raised and timedOut, "native failure and timeout outcomes were not preserved")
		for _, path in scopedPaths do
			assert(not fs.exists(path), "failed adapter scope remained after cleanup")
		end
		survivor "adapters-closed"
		b.close()
		assert(not fs.exists(directory .. "/b/studio-scope.json"), "second scope remained after cleanup")
		assert(
			outside.session.execute("Edit", "assert(game:GetAttribute('ScopeUnrelated')); return true").ok,
			"scope cleanup closed the unrelated Studio"
		)
	end)
	local failures: { string } = {}
	for index = #cleanup, 1, -1 do
		local closed, failure = pcall(function(): string?
			cleanup[index]()
			return nil
		end)
		if not closed then
			table.insert(failures, tostring(failure))
		end
	end
	assert(#failures == 0, table.concat(failures, "; "))
	assert(ok, problem)
	print "native scoped MCP: two real scopes, unrelated Studio, all-tool isolation, unknown tools, native adapter failure/timeout and cleanup passed"
end
