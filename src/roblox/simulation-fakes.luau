--!strict

local Types = require "./place-types"
local Environment = require "./environment"
local Datatypes = require "./datatypes"

type Binding = {
	next: number,
	period: number,
	priority: number,
	signal: Environment.Signal<number>,
	connection: Environment.Connection,
}

local function create(engine: Types.Engine)
	local environment = engine.environment
	local bindings: { Binding } = {}
	local now = 0
	local listening = false
	local function step(raw: unknown)
		assert(type(raw) == "number", "simulation step requires seconds")
		now += raw
		while true do
			local nextAt = math.huge
			for _, binding in bindings do
				if binding.connection.Connected then
					nextAt = math.min(nextAt, binding.next)
				end
			end
			if nextAt > now + 1e-9 then
				break
			end
			local due: { Binding } = {}
			for _, binding in bindings do
				if binding.connection.Connected and math.abs(binding.next - nextAt) < 1e-9 then
					table.insert(due, binding)
				end
			end
			table.sort(due, function(a: Binding, b: Binding)
				return a.priority < b.priority
			end)
			for _, binding in due do
				binding.next += binding.period
				if binding.connection.Connected then
					binding.signal:Fire(binding.period)
				end
			end
		end
	end
	return function(
		_service: Types.Instance,
		callback: (number) -> (),
		frequency: unknown,
		priority: number?
	): Environment.Connection
		local enabled = environment.propertyOf(engine.service "Workspace", "UseFixedSimulation")
		assert(enabled == engine.datatypes.Enum.RolloutState.Enabled, "BindToSimulation requires fixed simulation")
		assert(type(callback) == "function", "simulation callback must be a function")
		local rate = 30
		if frequency ~= nil then
			assert(Datatypes.enumType(frequency) == "StepFrequency", "simulation frequency must be a StepFrequency")
			local rates: { [unknown]: number } = {}
			for _, value in { 1, 5, 10, 15, 30, 60 } do
				rates[engine.datatypes.Enum.StepFrequency["Hz" .. tostring(value)]] = value
			end
			rate = assert(rates[frequency], "unsupported simulation frequency")
		end
		local order = priority or 2000
		assert(order % 1 == 0 and math.abs(order) < math.huge, "simulation priority must be a finite integer")
		if not listening then
			listening = true
			environment.event(engine.service "RunService", "PreSimulation"):Connect(step)
		end
		local signal: Environment.Signal<number> = environment.newSignal()
		local connection = signal:Connect(callback)
		table.insert(
			bindings,
			{ next = now + 1 / rate, period = 1 / rate, priority = order, signal = signal, connection = connection }
		)
		return connection
	end
end

return { create = create }
