--!strict

local digest = require "./hash"
local json = require "@std/json"
local task = require "@std/task"
local Core = require "../core"
local Transport = require "../core/transport"
local Wire = require "./wire"

export type Reply = {
	ok: boolean,
	text: string?,
	detail: string?,
	lost: boolean,
	expired: boolean,
}

export type Execute = (datamodel: string, code: string, replaySafe: boolean?) -> Reply

export type Options = {
	execute: Execute,
	datamodel: string,
	code: string,
	runId: string,
	deadline: number,
	pollSeconds: number?,
	segmentBytes: number?,
	onPoll: (() -> ())?,
	runner: boolean?,
}

export type Outcome = {
	status: "done" | "failed" | "session_lost" | "timed_out",
	text: string?,
	detail: string?,
}

local SEGMENT_BYTES = 24000
local POLL_SECONDS = 0.5

local function prefixFor(runId: string): string
	return "VerifyRun" .. string.sub(digest(runId), 1, 24) .. "_"
end

local function tokenFor(runId: string): string
	return string.sub(digest(runId), 1, 24)
end

local function header(prefix: string): string
	return "local RS = game:GetService('ReplicatedStorage')\nlocal P = " .. string.format("%q", prefix) .. "\n"
end

local publisher = [==[
R:SetAttribute("state", "running")
local function payload(name, text)
	local value = R:FindFirstChild(name)
	if value == nil then
		value = Instance.new("StringValue")
		value.Name = name
		value.Parent = R
	end
	value.Value = text
	return value
end
payload("error", "")
local function fingerprint(text)
	local hash = 2166136261
	for index = 1, #text do
		hash = bit32.bxor(hash, string.byte(text, index))
		hash = bit32.band(hash * 16777619, 0xFFFFFFFF)
	end
	return string.format("%08x-%d", hash, #text)
end
local function publish(ok, value)
	if not ok then
		payload("error", string.sub(tostring(value), 1, 4000))
		R:SetAttribute("state", "raised")
		return
	end
	local text = value
	if type(text) ~= "string" then
		local encoded, json = pcall(function()
			return game:GetService('HttpService'):JSONEncode(value)
		end)
		text = if encoded then json else tostring(value)
	end
	local cursor, index = 1, 0
	while cursor <= #text or index == 0 do
		local last = math.min(cursor + SIZE - 1, #text)
		while last < #text and last > cursor do
			local following = string.byte(text, last + 1)
			if following >= 128 and following < 192 then
				last -= 1
			else
				break
			end
		end
		index += 1
		local piece = string.sub(text, cursor, last)
		payload("p" .. index, piece):SetAttribute("digest", fingerprint(piece))
		cursor = last + 1
	end
	R:SetAttribute("count", index)
	R:SetAttribute("bytes", #text)
	R:SetAttribute("digest", fingerprint(text))
	R:SetAttribute("state", "done")
end
]==]

local function startSource(prefix: string, code: string, segmentBytes: number): string
	return header(prefix)
		.. "local SIZE = "
		.. tostring(segmentBytes)
		.. [==[

local R = RS:FindFirstChild(P)
if R ~= nil then
	return 'started'
end
R = Instance.new("Folder")
R.Name = P
R.Parent = RS
]==]
		.. publisher
		.. "task.spawn(function()\n\tlocal published, reason = pcall(function()\n\t\tpublish(pcall(function()\n"
		.. code
		.. "\n"
		.. [==[
end))
end)
if not published then
	payload("error", string.sub(tostring(reason), 1, 4000))
	R:SetAttribute("state", "raised")
end
end)
return 'started'
]==]
end

local REQUEST = "VerifyRequest"

local function runnerSource(rootName: string): string
	return "local RS = game:GetService('ReplicatedStorage')\nlocal ROOT = "
		.. string.format("%q", rootName)
		.. "\nlocal REQUEST = "
		.. string.format("%q", REQUEST)
		.. [==[

local context = if game:GetService('RunService'):IsServer() then 'Server' else 'Client'
local text = RS:GetAttribute(REQUEST)
local waited = 0
while type(text) ~= 'string' and context == 'Client' and waited < 10 do
	waited += task.wait(0.1)
	text = RS:GetAttribute(REQUEST)
end
if type(text) ~= 'string' then
	return
end
local request = game:GetService('HttpService'):JSONDecode(text)
local function work()
	return require(RS:WaitForChild(ROOT):WaitForChild(REQUEST))(request.runId, request.progressToken)
end
if request.context == 'Multiplayer' then
	if context == 'Server' then
		local ok, result = pcall(work)
		game:GetService('StudioTestService'):EndTest(if ok then result else { error = tostring(result) })
	end
	return
end
if request.context ~= context or RS:FindFirstChild(request.prefix) ~= nil then
	return
end
local SIZE = request.size
local R = Instance.new("Folder")
R.Name = request.prefix
R.Parent = RS
]==]
		.. publisher
		.. [==[
task.spawn(function()
	local published, reason = pcall(function()
		publish(pcall(work))
	end)
	if not published then
		payload("error", string.sub(tostring(reason), 1, 4000))
		R:SetAttribute("state", "raised")
	end
end)
]==]
end

local function requestSource(code: string): string
	return "return function(runId, progressToken)\n" .. code .. "\nend\n"
end

local function waitSource(prefix: string): string
	return header(prefix) .. "return if RS:WaitForChild(P, 10) ~= nil then 'started' else 'waiting'"
end

local function statusSource(prefix: string): string
	return header(prefix)
		.. [==[
local R = RS:FindFirstChild(P)
local state = if R ~= nil then R:GetAttribute("state") else nil
local out = { state = if state == nil then "absent" else state }
if state == "done" then
	out.count = R:GetAttribute("count")
	out.bytes = R:GetAttribute("bytes")
	out.digest = R:GetAttribute("digest")
elseif state == "raised" then
	local error = R:FindFirstChild("error")
	out.error = if error ~= nil then error.Value else nil
end
return game:GetService('HttpService'):JSONEncode(out)]==]
end

local function segmentSource(prefix: string, index: number): string
	return header(prefix)
		.. "local I = "
		.. tostring(index)
		.. [==[

local R = RS:FindFirstChild(P)
local value = if R ~= nil then R:FindFirstChild("p" .. I) else nil
return game:GetService('HttpService'):JSONEncode({
	index = I,
	count = R:GetAttribute("count"),
	digest = if value ~= nil then value:GetAttribute("digest") else nil,
	totalDigest = R:GetAttribute("digest"),
	totalBytes = R:GetAttribute("bytes"),
	payload = if value ~= nil then value.Value else nil,
})]==]
end

local function releaseSource(prefix: string): string
	return header(prefix) .. [==[
local R = RS:FindFirstChild(P)
if R ~= nil then
	R:Destroy()
end
return 'released']==]
end

local function record(text: string?): { [string]: unknown }?
	if text == nil then
		return nil
	end
	local parsed, value = pcall(Wire.parse, text)
	if parsed and type(value) == "table" then
		return Wire.record(value)
	end
	return nil
end

local function failure(reply: Reply, what: string): Outcome
	local detail = what .. ": " .. (reply.detail or "no detail")
	if reply.lost then
		return { status = "session_lost", detail = detail }
	end
	if reply.expired then
		return { status = "timed_out", detail = detail }
	end
	return { status = "failed", detail = detail }
end

local function fetch(options: Options, prefix: string, status: { [string]: unknown }): Outcome
	local count, bytes = status.count, status.bytes
	if
		type(count) ~= "number"
		or count < 1
		or count % 1 ~= 0
		or type(bytes) ~= "number"
		or type(status.digest) ~= "string"
	then
		return { status = "failed", detail = "transport: the engine reported a malformed result description" }
	end
	local segments: { Core.Segment } = {}
	for index = 1, count do
		local reply = options.execute(options.datamodel, segmentSource(prefix, index), true)
		if not reply.ok then
			return failure(reply, ("transport: segment %d of %d was not fetched"):format(index, count))
		end
		local fields = Transport.readSegment(record(reply.text))
		if fields == nil then
			return {
				status = "failed",
				detail = ("transport: segment %d of %d is missing or malformed in the engine"):format(index, count),
			}
		end
		if fields.index ~= index then
			return {
				status = "failed",
				detail = ("transport: requested segment %d of %d but the engine returned segment %d"):format(
					index,
					count,
					fields.index
				),
			}
		end
		if fields.count ~= count then
			return {
				status = "failed",
				detail = ("transport: segment %d claims %d segments but the engine reported %d"):format(
					index,
					fields.count,
					count
				),
			}
		end
		table.insert(segments, fields)
	end
	local rawSegments: { unknown } = {}
	for _, segment in segments do
		table.insert(rawSegments, segment)
	end
	local whole, reason = Core.reassembleSegments(rawSegments)
	if whole == nil then
		return { status = "failed", detail = "transport: " .. tostring(reason) }
	end
	if #whole ~= bytes or segments[1].totalDigest ~= status.digest then
		return {
			status = "failed",
			detail = "transport: the reassembled report does not match the engine's result description",
		}
	end
	return { status = "done", text = whole }
end

local function run(options: Options): Outcome
	local prefix = prefixFor(options.runId)
	local started = if options.runner == true
		then options.execute(options.datamodel, waitSource(prefix), true)
		else options.execute(
			options.datamodel,
			startSource(prefix, options.code, options.segmentBytes or SEGMENT_BYTES),
			true
		)
	while
		options.runner == true
		and started.ok
		and started.text ~= nil
		and string.find(started.text, "waiting", 1, true) ~= nil
		and os.clock() < options.deadline
	do
		started = options.execute(options.datamodel, waitSource(prefix), true)
	end
	if not started.ok then
		return failure(started, "the detached run did not start")
	end
	if options.runner == true and string.find(started.text or "", "started", 1, true) == nil then
		return { status = "timed_out", detail = "the place runner did not start the run before its deadline" }
	end
	if started.text == nil or string.find(started.text, "started", 1, true) == nil then
		return {
			status = "failed",
			detail = "the engine did not acknowledge the detached start: " .. string.sub(started.text or "", 1, 500),
		}
	end
	local problem: string? = nil
	while true do
		if options.onPoll ~= nil then
			pcall(options.onPoll)
		end
		if os.clock() >= options.deadline then
			return {
				status = "timed_out",
				detail = "the Studio run did not complete before its deadline"
					.. (if problem ~= nil then "; last poll problem: " .. problem else ""),
			}
		end
		local reply = options.execute(options.datamodel, statusSource(prefix), true)
		if not reply.ok then
			if reply.lost then
				return failure(reply, "the run poll lost the Studio session")
			end
			problem = reply.detail
		else
			local status = record(reply.text)
			if status == nil or type(status.state) ~= "string" then
				problem = "unreadable status: " .. string.sub(reply.text or "", 1, 200)
			elseif status.state == "absent" then
				return {
					status = "session_lost",
					detail = "session_lost: the run is gone from the Studio; the play session ended or Studio closed",
				}
			elseif status.state == "raised" then
				pcall(options.execute, options.datamodel, releaseSource(prefix), true)
				return {
					status = "failed",
					detail = "engine code raised: " .. tostring(status.error),
				}
			elseif status.state == "done" then
				local fetched = fetch(options, prefix, status)
				if fetched.status == "done" then
					pcall(options.execute, options.datamodel, releaseSource(prefix), true)
				end
				return fetched
			else
				problem = nil
			end
		end
		local remaining = options.deadline - os.clock()
		if remaining > 0 then
			task.wait(math.min(options.pollSeconds or POLL_SECONDS, remaining))
		end
	end
end

local function request(runId: string, context: string, progressToken: string?): string
	return json.serialize {
		context = context,
		prefix = prefixFor(runId),
		runId = runId,
		progressToken = progressToken,
		size = SEGMENT_BYTES,
	}
end

return {
	run = run,
	digest = digest,
	request = request,
	requestSource = requestSource,
	runnerSource = runnerSource,
	REQUEST = REQUEST,
	SEGMENT_BYTES = SEGMENT_BYTES,
	tokenFor = tokenFor,
}
