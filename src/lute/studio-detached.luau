--!strict

local crypto = require "@lute/crypto"
local task = require "@std/task"
local Core = require "../core"
local Wire = require "./wire"

export type Reply = {
	ok: boolean,
	text: string?,
	detail: string?,
	lost: boolean,
	expired: boolean,
}

export type Execute = (datamodel: string, code: string) -> Reply

export type Options = {
	execute: Execute,
	datamodel: string,
	code: string,
	runId: string,
	deadline: number,
	pollSeconds: number?,
	segmentBytes: number?,
	onPoll: (() -> ())?,
}

export type Outcome = {
	status: "done" | "failed" | "session_lost" | "timed_out",
	text: string?,
	detail: string?,
}

local SEGMENT_BYTES = 24000
local POLL_SECONDS = 0.5

local function digest(bytes: string): string
	local value = crypto.digest(crypto.hash.sha256, bytes)
	local out: { string } = {}
	for index = 0, buffer.len(value) - 1 do
		table.insert(out, string.format("%02x", buffer.readu8(value, index)))
	end
	return table.concat(out)
end

local function prefixFor(runId: string): string
	return "VerifyRun" .. string.sub(digest(runId), 1, 24) .. "_"
end

local function header(prefix: string): string
	return "local RS = game:GetService('ReplicatedStorage')\nlocal P = " .. string.format("%q", prefix) .. "\n"
end

local function startSource(prefix: string, code: string, segmentBytes: number): string
	return header(prefix)
		.. "local SIZE = "
		.. tostring(segmentBytes)
		.. [==[

for name in RS:GetAttributes() do
	if string.sub(name, 1, #P) == P then
		RS:SetAttribute(name, nil)
	end
end
RS:SetAttribute(P .. "state", "running")
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
		RS:SetAttribute(P .. "error", string.sub(tostring(value), 1, 4000))
		RS:SetAttribute(P .. "state", "raised")
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
		RS:SetAttribute(P .. "p" .. index, piece)
		RS:SetAttribute(P .. "d" .. index, fingerprint(piece))
		cursor = last + 1
	end
	RS:SetAttribute(P .. "count", index)
	RS:SetAttribute(P .. "bytes", #text)
	RS:SetAttribute(P .. "digest", fingerprint(text))
	RS:SetAttribute(P .. "state", "done")
end
task.spawn(function()
	publish(pcall(function()
]==]
		.. code
		.. "\nend))\nend)\nreturn 'started'"
end

local function statusSource(prefix: string): string
	return header(prefix)
		.. [==[
local state = RS:GetAttribute(P .. "state")
local out = { state = if state == nil then "absent" else state }
if state == "done" then
	out.count = RS:GetAttribute(P .. "count")
	out.bytes = RS:GetAttribute(P .. "bytes")
	out.digest = RS:GetAttribute(P .. "digest")
elseif state == "raised" then
	out.error = RS:GetAttribute(P .. "error")
end
return game:GetService('HttpService'):JSONEncode(out)]==]
end

local function segmentSource(prefix: string, index: number): string
	return header(prefix)
		.. "local I = "
		.. tostring(index)
		.. [==[

return game:GetService('HttpService'):JSONEncode({
	index = I,
	count = RS:GetAttribute(P .. "count"),
	digest = RS:GetAttribute(P .. "d" .. I),
	totalDigest = RS:GetAttribute(P .. "digest"),
	totalBytes = RS:GetAttribute(P .. "bytes"),
	payload = RS:GetAttribute(P .. "p" .. I),
})]==]
end

local function releaseSource(prefix: string): string
	return header(prefix)
		.. [==[
for name in RS:GetAttributes() do
	if string.sub(name, 1, #P) == P then
		RS:SetAttribute(name, nil)
	end
end
return 'released']==]
end

local function record(text: string?): { [string]: unknown }?
	if text == nil then
		return nil
	end
	local parsed, value: unknown = pcall(Wire.parse, text)
	if parsed and type(value) == "table" then
		return value :: { [string]: unknown }
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
		local reply = options.execute(options.datamodel, segmentSource(prefix, index))
		if not reply.ok then
			return failure(reply, ("transport: segment %d of %d was not fetched"):format(index, count))
		end
		local fields = record(reply.text)
		if
			fields == nil
			or type(fields.index) ~= "number"
			or type(fields.count) ~= "number"
			or type(fields.digest) ~= "string"
			or type(fields.totalDigest) ~= "string"
			or type(fields.totalBytes) ~= "number"
			or type(fields.payload) ~= "string"
		then
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
					fields.index :: number
				),
			}
		end
		if fields.count ~= count then
			return {
				status = "failed",
				detail = ("transport: segment %d claims %d segments but the engine reported %d"):format(
					index,
					fields.count :: number,
					count
				),
			}
		end
		table.insert(segments, {
			index = index,
			count = count,
			digest = fields.digest :: string,
			totalDigest = fields.totalDigest :: string,
			totalBytes = fields.totalBytes :: number,
			payload = fields.payload :: string,
		})
	end
	local whole, reason = Core.reassembleSegments(segments)
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
	local started =
		options.execute(options.datamodel, startSource(prefix, options.code, options.segmentBytes or SEGMENT_BYTES))
	if not started.ok then
		return failure(started, "the detached run did not start")
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
		local reply = options.execute(options.datamodel, statusSource(prefix))
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
				return {
					status = "failed",
					detail = "engine code raised: " .. tostring(status.error),
				}
			elseif status.state == "done" then
				local fetched = fetch(options, prefix, status)
				if fetched.status == "done" then
					pcall(options.execute, options.datamodel, releaseSource(prefix))
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

return {
	run = run,
	digest = digest,
	SEGMENT_BYTES = SEGMENT_BYTES,
	prefixFor = prefixFor,
	statusSource = statusSource,
	segmentSource = segmentSource,
}
