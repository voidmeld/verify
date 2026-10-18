--!strict

local fs = require "@std/fs"
local process = require "@std/process"
local json = require "@std/json"
local Eval = require "../src/agent-eval"
local Files = require "../src/lute/files"

return function()
	local directory = Files.claimDirectory(Files.temporary "verify-native-scope")
	local services = Eval.lute.services()
	local project = directory .. "/fixture.project.json"
	local place = directory .. "/fixture.rbxl"
	local payload = directory .. "/payload.luau"
	fs.writeStringToFile(payload, '--!strict\nreturn "left]]>right"\n')
	fs.writeStringToFile(
		project,
		Eval.lute.encode {
			name = "VerifyScope",
			tree = {
				["$className"] = "DataModel",
				Lighting = { ["$properties"] = { Technology = "Future" } },
				ReplicatedStorage = {
					["$className"] = "ReplicatedStorage",
					Payload = { ["$path"] = payload },
				},
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
	local owned = services.studio
	assert(owned ~= nil, "scoped Studio service missing")
	local provisioned = owned(tostring(process.cwd()), directory, place, { "rojo", "build", project, "-o", place }, 180)
	local ok, problem = pcall(function()
		local config = Eval.lute.decode(fs.readFileToString(provisioned.config)) :: {
			mcpServers: { studio: { command: string, args: { string } } },
		}
		local server = config.mcpServers.studio
		local argv = { server.command }
		for _, word in server.args do
			table.insert(argv, word)
		end
		local requests: { string } = {}
		local function request(method: string, params: unknown)
			table.insert(
				requests,
				json.serialize({
					jsonrpc = "2.0",
					id = #requests + 1,
					method = method,
					params = params,
				} :: json.Value)
			)
		end
		local function call(name: string, arguments: { [string]: unknown })
			request("tools/call", { name = name, arguments = arguments })
		end
		request("initialize", {})
		call("list_roblox_studios", {})
		call("execute_luau", { studio_id = "outside-this-run", datamodel_type = "Edit", code = "error('forwarded')" })
		call("execute_luau", {
			datamodel_type = "Edit",
			code = "assert(require(game.ReplicatedStorage.Payload) == 'left]]>right'); print('verify scoped console'); return 'scoped edit'",
		})
		call("screen_capture", {})
		call("start_stop_play", { is_start = true })
		call("input", {
			code = [[
task.wait(2)
local input = assert(game:GetService('UserInputService'):CreateVirtualInput())
input:SendKey(true, Enum.KeyCode.Space, false)
task.wait(0.1)
input:SendKey(false, Enum.KeyCode.Space, false)
return 'scoped input'
]],
		})
		call("get_console_output", {})
		call("start_stop_play", { is_start = false })
		local input = directory .. "/requests.jsonl"
		fs.writeStringToFile(input, table.concat(requests, "\n") .. "\n")
		local result = services.execute { argv = argv, input = input, deadlineSeconds = 180 }
		assert(
			result.started and result.exitcode == 0 and not result.timedOut,
			"scoped proxy failed or timed out: " .. result.stderr
		)
		local responses: { { id: number, result: unknown?, error: unknown? } } = {}
		for line in string.gmatch(result.stdout, "[^\r\n]+") do
			local reply = Eval.lute.decode(line) :: { id: number, result: unknown?, error: unknown? }
			responses[reply.id] = reply
		end
		assert(#responses == #requests, "scoped proxy lost responses: " .. result.stdout)
		for index, reply in responses do
			assert((reply.error ~= nil) == (index == 3), Eval.lute.encode(reply))
		end
		local listing = responses[2].result :: { content: { { text: string } } }
		local studios = Eval.lute.decode(listing.content[1].text) :: { studios: { { id: string } } }
		assert(#studios.studios == 1 and studios.studios[1].id ~= "", "scope must expose exactly one Studio")
		local capture = responses[5].result :: { content: { { type: string } } }
		local image = false
		for _, content in capture.content do
			image = image or content.type == "image"
		end
		assert(image, "scoped capture lost its image")
	end)
	provisioned.close()
	assert(not fs.exists(directory .. "/studio-scope.json"), "scope remained after cleanup")
	assert(ok, problem)
	print "native scoped MCP: provisioning, isolation, execution, play, input, capture, console and cleanup passed"
end
