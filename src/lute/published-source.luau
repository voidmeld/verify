--!strict

local Place = require "./place"

export type Options = {
	output: string,
	entry: string,
	frameworkDirectory: string?,
	roots: { string }?,
	authorizedUserIds: { number },
	context: ("Server" | "Client")?,
}
local function imports(framework: string, entry: string): string
	return "local Core = require("
		.. Place.moduleExpression(framework .. "/src/core/init.luau")
		.. ")\n"
		.. "local Entry = require("
		.. Place.moduleExpression(framework .. "/src/roblox/case-entry.luau")
		.. ")\n"
		.. "local Channel = require("
		.. Place.moduleExpression(framework .. "/src/roblox/report-channel.luau")
		.. ")\n"
		.. "local function loadFactory() return require("
		.. Place.moduleExpression(entry)
		.. ") end\n"
end
local execution = [[
local function execute(request: {runId: string, cases: {string}?})
 local ok, result = pcall(function() return Entry.run(loadFactory(), 'player', request.cases) end)
 if ok then return result end
 return Core.syntheticReport {
  executor='roblox-player', environment={host='player'},
  id='verify:execution', name='published host execution', status='failed', message=tostring(result),
 }
end
]]
local validation = [[
local used: {[Player]: boolean} = setmetatable({}, {__mode='k'})
local function authorize(player: Player): {runId: string, cases: {string}?}
 assert(allowed[player.UserId], 'published verification caller is not authorized')
 assert(not used[player], 'published verification already executed for this player')
 local data = player:GetJoinData().LaunchData
 assert(type(data)=='string' and #data>0, 'published verification requires launch data')
 local value: unknown = game:GetService('HttpService'):JSONDecode(data)
 assert(type(value)=='table', 'invalid verification launch data')
 local request = value :: {[string]: unknown}
 assert(type(request.verifyRun)=='string' and request.verifyRun~='', 'verification run identity is missing')
 assert(request.verifyEntry==expectedEntry, 'verification entry does not match this fixture')
 local ids: {string}? = nil
 if request.verifyCases~=nil then
  assert(type(request.verifyCases)=='table', 'case selection must be an array')
  local values=request.verifyCases :: {[unknown]: unknown}
  local selected: {string}={}
  local seen: {[string]: boolean}={}
  local count=0
  for key,id in values do
   assert(type(key)=='number' and key>=1 and key%1==0, 'case selection must be a dense array')
   assert(type(id)=='string' and id~='' and not seen[id], 'invalid or duplicate selected case')
   seen[id]=true
   count+=1
   selected[key]=id
  end
  assert(count>0 and count==#selected, 'case selection must be nonempty and dense')
  for index=1,count do assert(selected[index]~=nil, 'case selection must be dense') end
  ids=selected
 end
 used[player]=true
 return {runId=request.verifyRun,cases=ids}
end
]]
local function build(options: Options)
	assert(type(options.output) == "string" and options.output ~= "", "published fixture requires output")
	assert(type(options.entry) == "string" and options.entry ~= "", "published fixture requires entry")
	assert(
		options.context == nil or options.context == "Server" or options.context == "Client",
		"invalid published execution context"
	)
	assert(type(options.authorizedUserIds) == "table", "published fixture requires authorized user IDs")
	local allowed: { [number]: boolean } = {}
	local ids: { string } = {}
	local count = 0
	for index, id in options.authorizedUserIds do
		assert(type(index) == "number" and index >= 1 and index % 1 == 0, "authorized user IDs must be a dense array")
		assert(
			type(id) == "number" and id > 0 and id < math.huge and id % 1 == 0 and not allowed[id],
			"invalid or duplicate authorized user ID"
		)
		allowed[id] = true
		count += 1
		table.insert(ids, "[" .. string.format("%.0f", id) .. "]=true")
	end
	assert(count > 0 and count == #options.authorizedUserIds, "authorized user IDs must be nonempty and dense")
	for index = 1, count do
		assert(options.authorizedUserIds[index] ~= nil, "authorized user IDs must be dense")
	end
	table.sort(ids)
	local framework = options.frameworkDirectory or "."
	assert(framework ~= "", "framework directory must not be empty")
	local header = "--!strict\n"
	local server = header
		.. "local allowed: {[number]: boolean} = {"
		.. table.concat(ids, ",")
		.. "}\n"
		.. "local expectedEntry="
		.. string.format("%q", options.entry)
		.. "\n"
		.. validation
	local client = header .. imports(framework, options.entry)
	if options.context == "Client" then
		server ..= [[local remote=Instance.new('RemoteFunction')
remote.Name='VerifyPublishedRun'
remote.OnServerInvoke=function(player: Player) return authorize(player) end
remote.Parent=game:GetService('ReplicatedStorage')
]]
		client ..= execution .. [[local remote=game:GetService('ReplicatedStorage'):WaitForChild('VerifyPublishedRun') :: RemoteFunction
local request=remote:InvokeServer() :: {runId: string, cases: {string}?}
local report=execute(request)
Channel.publish(request.runId, report, function(value) return game:GetService('HttpService'):JSONEncode(value) end, print)
]]
	else
		server ..= imports(framework, options.entry) .. execution .. [[local remote=Instance.new('RemoteFunction')
remote.Name='VerifyPublishedRun'
remote.OnServerInvoke=function(player: Player)
 local request=authorize(player)
 return Channel.envelope(request.runId,execute(request))
end
remote.Parent=game:GetService('ReplicatedStorage')
]]
		client ..= [[local remote=game:GetService('ReplicatedStorage'):WaitForChild('VerifyPublishedRun') :: RemoteFunction
local response=remote:InvokeServer()
local report=Channel.receive(response,response.runId)
Channel.publish(response.runId, report, function(value) return game:GetService('HttpService'):JSONEncode(value) end, print)
]]
	end
	local roots = { framework .. "/src/core", framework .. "/src/roblox" }
	local extra: { string } = options.roots or {}
	for _, root in extra do
		assert(type(root) == "string" and root ~= "", "invalid module root")
		table.insert(roots, root)
	end
	Place.build {
		output = options.output,
		roots = roots,
		modules = { options.entry },
		serverSource = server,
		clientSource = client,
	}
end
return { build = build }
