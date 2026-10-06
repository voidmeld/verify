--!strict
--!nolint DeprecatedApi

local Core = require "../../src/core"
local Roblox = require "../../src/roblox"
local Multi = Roblox.multiplayer
local Native = Roblox.experienceHost
local Case = require "./case"
type Object = {
	Name: string,
	Parent: unknown,
	Value: number,
	Destroy: (Object) -> (),
	GetAttribute: (Object, string) -> unknown,
	SetAttribute: (Object, string, unknown) -> (),
}
type Remote = Object & Roblox.MultiplayerRemote & {
	OnServerEvent: { Connect: (unknown, (Roblox.MultiplayerPlayer) -> ()) -> Roblox.MultiplayerConnection },
}
type Globals = {
	game: { GetService: (unknown, string) -> unknown },
	Instance: { new: (string) -> unknown },
	task: {
		wait: (number) -> (),
	},
}
local factory: Roblox.CaseEntryFactory = function(host)
	if host == "simulator" then
		local time, count, pressed = 0, 0, false
		local now = function()
			return time
		end
		local sleep = function(seconds: number)
			time += seconds
		end
		return {
			cases = {
				Case(sleep, {
					"Explicit shared-state and input fake; this run proves no engine replication, UI activation or rendered pixels.",
				}),
			},
			now = now,
			options = {
				executor = "simulated-multiplayer",
				bind = function()
					return {
						name = "simulated-multiplayer",
						capabilities = { "query:counter", "query:button", "action:input.pointer", "capture" },
						environment = { host = "simulator" },
						now = now,
						sleep = sleep,
						invoke = function(request: Core.OperationRequest): unknown
							assert(
								request.actor == "server" or request.actor == "client-1" or request.actor == "client-2",
								"unknown actor"
							)
							if request.name == "counter" then
								return count
							end
							assert(request.actor == "client-1", "input target must be first client")
							if request.name == "button" then
								return { x = 320, y = 250 }
							end
							assert(request.name == "input.pointer", "unknown operation")
							local pointer = request.payload :: { x: number, y: number, down: boolean }
							assert(pointer.x == 320 and pointer.y == 250, "pointer missed button")
							if pressed and not pointer.down then
								count += 1
							end
							pressed = pointer.down
							return nil
						end,
						capture = function(actor, checkpoint)
							return {
								{
									name = checkpoint,
									reference = "simulated-state://" .. actor .. "/" .. tostring(count),
									mediaType = "application/x-verify-simulated-state",
								},
							}
						end,
						close = function()
							pressed = false
						end,
					}
				end,
			},
		}
	end
	assert(host == "studio", "this fixture requires coordinated Studio clients")
	local globals = (getfenv(0) :: unknown) :: Globals
	local storage = globals.game:GetService "ReplicatedStorage" :: Object
	local players = globals.game:GetService "Players"
	local now = os.clock
	local sleep = globals.task.wait
	return {
		cases = {
			Case(sleep, {
				"Client captures are temporary in-session references; this case does not prove durable screenshot export.",
			}),
		},
		now = now,
		options = {
			executor = "roblox-studio",
			bind = function(context)
				local remote = globals.Instance.new "RemoteEvent" :: Remote
				remote.Name = "VerifyActors"
				local click = globals.Instance.new "RemoteEvent" :: Remote
				click.Name = "Click"
				local counter = globals.Instance.new "IntValue" :: Object
				counter.Name = "Counter"
				context:defer(function()
					remote:Destroy()
					click:Destroy()
					counter:Destroy()
				end)
				local connection = click.OnServerEvent:Connect(function(player)
					if player.Parent == players then
						counter.Value += 1
					end
				end)
				context:defer(function()
					connection:Disconnect()
				end)
				remote.Parent = storage
				click.Parent = storage
				counter.Parent = storage
				local runId = storage:GetAttribute "VerifyRun"
				assert(type(runId) == "string")
				return Multi.server(context, {
					remote = remote,
					runId = runId,
					clients = 2,
					authorize = function(player)
						return player.Parent == players
					end,
					registry = {
						actions = {},
						queries = {
							counter = {
								run = function()
									return counter.Value
								end,
							},
						},
					},
					engine = Native.nativeEngine(),
					sleep = sleep,
					deadlineSeconds = 20,
					armed = function()
						remote:SetAttribute("Armed", true)
					end,
				})
			end,
		},
	}
end
return factory
