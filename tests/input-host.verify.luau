--!strict
local Core = require "../src/core"
local Input = require "../src/roblox/input-host"
return function(suite: Core.Harness)
	suite:suite("semantic input adapter", function()
		suite:case("rejects malformed keys, pointers and text", function(check)
			local badKeys: { unknown } = { {}, { code = "", down = true }, { code = "A", down = 1 } }
			for _, value in badKeys do
				check:expect((pcall(Input.key.input, value))):toEqual(false)
			end
			local badPointers: { unknown } = {
				{ x = math.huge, y = 1, button = "left", down = true },
				{ x = math.huge - math.huge, y = 1, button = "left", down = true },
				{ x = 1, y = 2, button = "extra", down = true },
				{ x = 1, y = 2, button = "left", down = "yes" },
			}
			for _, value in badPointers do
				check:expect((pcall(Input.pointer.input, value))):toEqual(false)
			end
			check:expect((pcall(Input.text.input, 1))):toEqual(false)
			check:expect(Input.pointer.input({ x = 0, y = -1, button = "middle", down = false }).y):toEqual(-1)
		end)
		suite:case("registry forwards typed input and preserves backend failures", function(check)
			local received: { string } = {}
			local registry = Input.registry {
				key = function(value)
					table.insert(received, value.code)
				end,
				pointer = function(value)
					table.insert(received, value.button)
				end,
				text = function(value)
					if value == "fail" then
						error "backend failure"
					end
					table.insert(received, value)
				end,
				close = function() end,
			}
			local function run(name: string, payload: unknown): unknown
				return registry.actions[name].run(
					payload,
					{ kind = "action", actor = "client", name = name, payload = payload, deadline = 10 }
				)
			end
			run("input.key", { code = "A", down = true })
			run("input.pointer", { x = 10, y = 20, button = "right", down = false })
			run("input.text", "hello")
			check:expect(table.concat(received, ",")):toEqual "A,right,hello"
			check:expect((pcall(run, "input.text", "fail"))):toEqual(false)
			check:expect((pcall(run, "input.pointer", { x = math.huge }))):toEqual(false)
			check:expect(#received):toEqual(3)
		end)
	end)
end
