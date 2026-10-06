--!strict

local net = require "@std/net"
local process = require "@std/process"
local OpenCloud = require "../src/lute/open-cloud"

local ORIGIN = "https://apis.roblox.com/cloud/v2/"

local function request(call: OpenCloud.Call, _deadline: number): OpenCloud.Exchange
	local key = process.env["OPEN_CLOUD_API_KEY"]
	if key == nil or key == "" then
		return { status = "unsent", detail = "OPEN_CLOUD_API_KEY is not set in this process" }
	end
	local headers: { [string]: string } = { ["x-api-key"] = key, Accept = "application/json" }
	if call.body ~= nil then
		headers["Content-Type"] = "application/json"
	end
	local method: string = call.method
	local sent, response: unknown = pcall(net.request, call.url, {
		method = method,
		headers = headers,
		body = call.body,
	})
	if not sent then
		return { status = "unanswered", detail = tostring(response) }
	end
	local answer = response :: { status: number, body: string }
	return { status = "answered", httpStatus = answer.status, body = answer.body }
end

local function authorize(call: OpenCloud.Call): OpenCloud.Authorization
	if string.sub(call.url, 1, #ORIGIN) ~= ORIGIN then
		return { ok = false, reason = "request leaves the Open Cloud origin" }
	end
	return { ok = true, reason = nil }
end

return { request = request, authorize = authorize }
