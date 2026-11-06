--!strict

local Environment = require "./environment-types"
local Data = require "./message-data"

type Instance = Environment.Instance
local joins: { [Instance]: unknown } = setmetatable({}, { __mode = "ks" })
local arrivals: { [Instance]: unknown } = setmetatable({}, { __mode = "ks" })

local function setJoinData(environment: Environment.Environment, player: Instance, data: { [string]: unknown })
	assert(environment.isAlive(player) and player:IsA "Player", "join data requires a live Player in this environment")
	joins[player] = Data.copy(data, true)
end

local function setLocalPlayerTeleportData(environment: Environment.Environment, service: Instance, data: unknown)
	assert(
		environment.isAlive(service) and service:IsA "TeleportService",
		"teleport data requires a live TeleportService in this environment"
	)
	arrivals[service] = Data.copy(data, true)
end

local function attach(environment: Environment.Environment)
	local options: { [Instance]: unknown } = setmetatable({}, { __mode = "ks" })
	environment.fake("TeleportOptions.SetTeleportData", function(object: Instance, value: unknown)
		options[object] = Data.copy(value, true)
	end)
	environment.fake("TeleportOptions.GetTeleportData", function(object: Instance): unknown
		return Data.copy(options[object], true)
	end)
	environment.fake("Player.GetJoinData", function(player: Instance): unknown
		return Data.copy(joins[player] or {}, true)
	end)
	environment.fake("TeleportService.GetLocalPlayerTeleportData", function(service: Instance): unknown
		return Data.copy(arrivals[service], true)
	end)
	environment.onClone(function(source, target)
		if source:IsA "TeleportOptions" then
			options[target] = Data.copy(options[source], true)
		end
	end)
end

return { attach = attach, setJoinData = setJoinData, setLocalPlayerTeleportData = setLocalPlayerTeleportData }
