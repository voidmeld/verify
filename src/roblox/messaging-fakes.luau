--!strict

local Environment = require "./environment-types"
local Data = require "./message-data"

type Subscription = { signal: Environment.Signal, connection: Environment.Connection }

local function topicName(topic: string)
	assert(type(topic) == "string" and #topic >= 1 and #topic <= 80, "messaging topic must contain 1 to 80 characters")
end

local function attach(environment: Environment.Environment)
	local services: { [Environment.Instance]: { [string]: { Subscription } } } = setmetatable({}, { __mode = "ks" })
	environment.fake(
		"MessagingService.SubscribeAsync",
		function(service: Environment.Instance, topic: string, receive: (unknown) -> ()): Environment.Connection
			topicName(topic)
			assert(type(receive) == "function", "messaging callback must be a function")
			local topics = services[service] or {}
			services[service] = topics
			local subscriptions = topics[topic] or {}
			topics[topic] = subscriptions
			local signal: Environment.Signal = environment.newSignal()
			local connection = signal:Connect(function(message: unknown, ...: unknown)
				receive(message)
			end)
			table.insert(subscriptions, { signal = signal, connection = connection })
			return connection
		end
	)
	environment.fake(
		"MessagingService.PublishAsync",
		function(service: Environment.Instance, topic: string, payload: unknown)
			topicName(topic)
			local data = Data.copy(payload, false)
			local sent = math.floor(environment.now())
			local topics = services[service]
			local subscriptions = if topics then topics[topic] else nil
			if subscriptions == nil then
				return
			end
			for index = #subscriptions, 1, -1 do
				local subscription = subscriptions[index]
				if not subscription.connection.Connected then
					table.remove(subscriptions, index)
					continue
				end
				environment.scheduler.defer(function()
					if environment.isAlive(service) then
						subscription.signal:Fire { Data = Data.copy(data, false), Sent = sent }
					end
				end)
			end
		end
	)
	environment.observe(function(event)
		local topics = services[event.object]
		if topics then
			for _, subscriptions in topics do
				for _, subscription in subscriptions do
					subscription.connection:Disconnect()
				end
			end
			services[event.object] = nil
		end
	end, { operations = { "destroy" } })
end

return { attach = attach }
