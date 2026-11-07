--!strict

local Types = require "./place-types"
local Environment = require "./environment"
local Vectors = require "./datatypes/vector"

export type Options = {
	player: Types.Instance,
	visible: (Types.Instance, Vectors.Vector3Value, Vectors.Vector3Value) -> boolean,
}

local function simulated(engine: Types.Engine, options: Options): Environment.Connection
	local env = engine.environment
	local workspace = engine.service "Workspace"
	local service = engine.service "ProximityPromptService"
	local prompts: { Types.Instance } = {}
	local shown: { [Types.Instance]: boolean } = {}
	local holds: { [Types.Instance]: { triggered: boolean, holding: boolean } } = {}
	local connected = true
	local function added(object: Environment.Object)
		if object:IsA "ProximityPrompt" then
			table.insert(prompts, env.assertInstance(object))
		end
	end
	for _, object in workspace:GetDescendants() do
		added(object)
	end
	local created = env.onCreate(added)
	local function point(object: Types.Instance): Vectors.Vector3Value?
		if object:IsA "Attachment" then
			return Vectors.expect3(object.WorldPosition, 1)
		elseif object:IsA "BasePart" then
			return Vectors.expect3(object.Position, 1)
		elseif object:IsA "Model" then
			local primary = object.PrimaryPart
			return if primary ~= nil then Vectors.expect3(env.assertInstance(primary).Position, 1) else nil
		end
		return nil
	end
	local function emit(prompt: Types.Instance, event: string)
		if env.isAlive(prompt) then
			env.fire(prompt, event, options.player)
		end
		env.fire(
			service,
			if event == "Triggered"
				then "PromptTriggered"
				elseif event == "TriggerEnded" then "PromptTriggerEnded"
				else event,
			prompt,
			options.player
		)
	end
	local function cancel(prompt: Types.Instance)
		local hold = holds[prompt]
		if hold ~= nil then
			holds[prompt] = nil
			if hold.holding then
				emit(prompt, "PromptButtonHoldEnded")
			end
			if hold.triggered then
				emit(prompt, "TriggerEnded")
			end
		end
	end
	local function eligible(prompt: Types.Instance): boolean
		if
			not connected
			or not env.isAlive(prompt)
			or not prompt:IsDescendantOf(workspace)
			or service.Enabled ~= true
			or prompt.Enabled ~= true
		then
			return false
		end
		local characterValue = options.player.Character
		local character = if characterValue ~= nil then env.assertInstance(characterValue) else nil
		local root = if character ~= nil then character:FindFirstChild "HumanoidRootPart" else nil
		local parent = prompt.Parent
		local origin = if root ~= nil then point(root) else nil
		local target = if parent ~= nil then point(parent) else nil
		if origin == nil or target == nil then
			return false
		end
		local range = prompt.MaxActivationDistance
		assert(
			type(range) == "number" and range >= 0 and range < math.huge,
			"prompt range must be finite and nonnegative"
		)
		local x, y, z = origin.X - target.X, origin.Y - target.Y, origin.Z - target.Z
		return math.sqrt(x * x + y * y + z * z) <= range and options.visible(prompt, origin, target)
	end
	local function refresh()
		for _, prompt in prompts do
			local available = eligible(prompt)
			if available and not shown[prompt] then
				shown[prompt] = true
				env.fire(prompt, "PromptShown", engine.datatypes.Enum.ProximityPromptInputType.Keyboard)
				env.fire(service, "PromptShown", prompt, engine.datatypes.Enum.ProximityPromptInputType.Keyboard)
			elseif not available and shown[prompt] then
				shown[prompt] = nil
				cancel(prompt)
				if env.isAlive(prompt) then
					env.fire(prompt, "PromptHidden")
				end
				env.fire(service, "PromptHidden", prompt)
			end
		end
	end
	local function begin(prompt: Types.Instance)
		refresh()
		if not shown[prompt] or holds[prompt] ~= nil then
			return
		end
		local duration = prompt.HoldDuration
		assert(
			type(duration) == "number" and duration >= 0 and duration < math.huge,
			"prompt hold must be finite and nonnegative"
		)
		local started = { triggered = false, holding = duration > 0 }
		holds[prompt] = started
		if duration > 0 then
			emit(prompt, "PromptButtonHoldBegan")
		end
		env.scheduler.delay(duration, function()
			if holds[prompt] == started and eligible(prompt) then
				started.triggered = true
				emit(prompt, "Triggered")
			end
		end)
	end
	env.fake("ProximityPrompt.InputHoldBegin", begin)
	env.fake("ProximityPrompt.InputHoldEnd", cancel)
	local input = engine.service "UserInputService"
	local began = env.event(input, "InputBegan"):Connect(function(value: unknown, processed: unknown)
		if processed == true then
			return
		end
		refresh()
		for _, prompt in prompts do
			if shown[prompt] and prompt.KeyboardKeyCode == Environment.read(value, "KeyCode") then
				begin(prompt)
			end
		end
	end)
	local ended = env.event(input, "InputEnded"):Connect(function(value: unknown)
		for _, prompt in prompts do
			if env.isAlive(prompt) and prompt.KeyboardKeyCode == Environment.read(value, "KeyCode") then
				cancel(prompt)
			end
		end
	end)
	local heartbeat = env.event(engine.service "RunService", "Heartbeat"):Connect(refresh)
	return {
		Connected = true,
		Disconnect = function(self: Environment.Connection)
			self.Connected = false
			connected = false
			refresh()
			created:Disconnect()
			began:Disconnect()
			ended:Disconnect()
			heartbeat:Disconnect()
		end,
	}
end

return { simulated = simulated }
