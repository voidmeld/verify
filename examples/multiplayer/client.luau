--!strict
--!nolint DeprecatedApi

local Roblox = require "../../src/roblox"
local Input = Roblox.inputHost
local Multi = Roblox.multiplayer
type Object = { WaitForChild: (Object, string) -> unknown, GetAttribute: (Object, string) -> unknown }
type Gui = { IgnoreGuiInset: boolean, Parent: unknown, Destroy: (Gui) -> () }
type Button = Roblox.InputGuiTarget & {
	Size: unknown,
	Position: unknown,
	Text: string,
	Parent: unknown,
	Activated: { Connect: (unknown, () -> ()) -> Roblox.MultiplayerConnection },
}
type Globals = {
	game: { GetService: (unknown, string) -> unknown },
	Instance: { new: (string) -> unknown },
	UDim2: { fromOffset: (number, number) -> unknown },
	task: { wait: (number?) -> (), spawn: (() -> ()) -> () },
}
return function()
	local globals = (getfenv(0) :: unknown) :: Globals
	local storage = globals.game:GetService "ReplicatedStorage" :: Object
	local remote = storage:WaitForChild "VerifyActors" :: Object & Roblox.MultiplayerRemote
	local counter = storage:WaitForChild "Counter" :: { Value: number }
	local click = storage:WaitForChild "Click" :: Roblox.MultiplayerRemote
	local input = Input.native()
	assert(input, "supported virtual input unavailable")
	local gui = globals.Instance.new "ScreenGui" :: Gui
	gui.IgnoreGuiInset = true
	local players = globals.game:GetService "Players" :: { LocalPlayer: Object }
	gui.Parent = players.LocalPlayer:WaitForChild "PlayerGui"
	local button = globals.Instance.new "TextButton" :: Button
	button.Size = globals.UDim2.fromOffset(240, 100)
	button.Position = globals.UDim2.fromOffset(200, 200)
	button.Text = "Advance shared state"
	button.Parent = gui
	button.Activated:Connect(function()
		click:FireServer(nil)
	end)
	local registry = Input.registry(input)
	registry.queries.counter = {
		run = function()
			return counter.Value
		end,
	}
	registry.queries.button = {
		run = function()
			return Input.screenCenter(button)
		end,
	}
	while not remote:GetAttribute "Armed" do
		globals.task.wait()
	end
	local runId = storage:GetAttribute "VerifyRun"
	assert(type(runId) == "string")
	Multi.client {
		remote = remote,
		runId = runId,
		registry = registry,
		capabilities = { "action:input.pointer", "query:counter", "query:button" },
		now = os.clock,
		spawn = globals.task.spawn,
		close = function()
			input.close()
			gui:Destroy()
		end,
		capture = function(name)
			local id: string? = nil
			local capture =
				globals.game:GetService "CaptureService" :: { CaptureScreenshot: (unknown, (string) -> ()) -> () }
			capture:CaptureScreenshot(function(value)
				id = value
			end)
			local deadline = os.clock() + 8
			repeat
				globals.task.wait()
			until id ~= nil or os.clock() > deadline
			assert(id, "capture callback timed out")
			return { { name = name, reference = id, mediaType = "image/png" } }
		end,
	}
end
