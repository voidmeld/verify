--!strict

local Core = require "../src/core"

local function text(value: unknown): string
	assert(type(value) == "string", "expected text")
	return value
end

return function(harness: Core.Harness)
	harness:suite("bound operation hosts", function()
		harness:case("routes distinct operation kinds and retains request identity", function(check)
			local query = Core.operation { kind = "query", name = "echo", input = text, output = text }
			local action = Core.operation { kind = "action", name = "echo", input = text, output = text }
			local requests: { Core.OperationRequest } = {}
			local host = Core.operationHost {
				name = "injected",
				environment = { runtime = "memory" },
				now = function()
					return 4
				end,
				bound = {
					Core.bindHostOperation(query, function(value, request)
						table.insert(requests, request)
						return "query:" .. value
					end),
					Core.bindHostOperation(action, function(value)
						return "action:" .. value
					end),
				},
			}
			local request: Core.OperationRequest = {
				kind = "query",
				actor = "first",
				name = "echo",
				payload = "value",
				deadline = 8,
			}
			check:expect(host.invoke(request)):toEqual "query:value"
			check:expect(requests[1] == request):toEqual(true)
			request.kind = "action"
			check:expect(host.invoke(request)):toEqual "action:value"
			check:expect(host.capabilities):toEqual { "query:echo", "action:echo" }
			check:expect(host.environment.runtime):toEqual "memory"
			check:expect(host.now()):toEqual(4)
		end)

		harness:case("retains endpoint input and output validation and refuses missing operations", function(check)
			local operation = Core.operation { kind = "query", name = "text", input = text, output = text }
			local host = Core.operationHost {
				name = "validated",
				environment = {},
				now = function()
					return 0
				end,
				bound = { Core.bindHostOperation(operation, function(value)
					return value
				end) },
			}
			local request: Core.OperationRequest = {
				kind = "query",
				actor = "first",
				name = "text",
				payload = false,
				deadline = 8,
			}
			check:expect((pcall(host.invoke, request))):toEqual(false)
			request.payload = "value"
			request.name = "missing"
			check:expect((pcall(host.invoke, request))):toEqual(false)
			local invalidOutput: Core.OperationBinding = {
				key = "query:text",
				endpoint = Core.bindOperation(
					Core.operation {
						kind = "query",
						name = "text",
						input = text,
						output = function(value: unknown): string
							assert(text(value) == "accepted", "output refused")
							return "accepted"
						end,
					},
					function(): string
						return "refused"
					end
				),
			}
			local invalid = Core.operationHost {
				name = "invalid-output",
				environment = {},
				now = host.now,
				bound = { invalidOutput },
			}
			request.name = "text"
			check:expect((pcall(invalid.invoke, request))):toEqual(false)
		end)

		harness:case("exposes capture only when supplied and delegates time seams", function(check)
			local elapsed = 0
			local seenActor, seenCheckpoint = "", ""
			local host = Core.operationHost {
				name = "capture",
				environment = {},
				bound = {},
				now = function()
					return elapsed
				end,
				sleep = function(seconds)
					elapsed += seconds
				end,
				capture = function(actor, checkpoint)
					seenActor, seenCheckpoint = actor, checkpoint
					return {}
				end,
			}
			check:expect(host.capabilities):toEqual { "capture" }
			assert(host.sleep)(2)
			check:expect(host.now()):toEqual(2)
			check:expect(assert(host.capture)("second", "pose")):toEqual {}
			check:expect(seenActor):toEqual "second"
			check:expect(seenCheckpoint):toEqual "pose"
		end)
	end)
end
