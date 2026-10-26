--!strict

local Schema = require "./schema"

export type Tool = { name: string, description: string, inputSchema: { [string]: unknown } }
export type Backend = { call: (name: string, arguments: { [string]: unknown }) -> unknown }
export type Scope = { dispatch: (method: string, params: unknown) -> unknown, close: () -> () }

local ALLOWED =
	{ start_stop_play = true, screen_capture = true, execute_luau = true, get_console_output = true, input = true }

local function create(studio: { id: string, name: string }, backend: Backend, encode: (unknown) -> string): Scope
	assert(studio.id ~= "", "a scope requires one Studio id")
	local target = table.clone(studio)
	local closed = false
	local function text(value: unknown): unknown
		return { content = { { type = "text", text = encode(value) } } }
	end
	local function forward(name: string, arguments: { [string]: unknown }): unknown
		local ok, result = pcall(backend.call, name, arguments)
		assert(ok, "the scoped Studio call failed; inspect this run's console")
		if type(result) == "table" and (result :: { [string]: unknown }).isError == true then
			error("the scoped Studio tool returned an error; inspect this run's console", 0)
		end
		return result
	end
	local function dispatch(method: string, params: unknown): unknown
		assert(not closed, "the run scope is closed")
		if method == "initialize" then
			return {
				protocolVersion = "2025-06-18",
				capabilities = { tools = { listChanged = false } },
				serverInfo = { name = "verify-scoped-studio", version = "1" },
			}
		elseif method == "ping" then
			return {}
		elseif method == "tools/list" then
			local tools: { Tool } = {}
			local fields: { [string]: { [string]: unknown } } = {
				studio_id = { type = "string", enum = { target.id } },
				code = { type = "string" },
				datamodel_type = { type = "string", enum = { "Edit", "Client", "Server" } },
				is_start = { type = "boolean" },
				capture_id = { type = "string" },
			}
			local function add(name: string, description: string, required: { string }, optional: { string }?)
				local properties: { [string]: unknown } = { studio_id = fields.studio_id }
				for _, key in required do
					properties[key] = fields[key]
				end
				local optionalKeys: { string } = optional or {}
				for _, key in optionalKeys do
					properties[key] = fields[key]
				end
				local schema: { [string]: unknown } = {
					type = "object",
					properties = properties,
					additionalProperties = false,
				}
				if #required > 0 then
					schema.required = required
				end
				table.insert(tools, {
					name = name,
					description = description .. " Operates only on the Studio owned by this run.",
					inputSchema = schema,
				})
			end
			add("list_roblox_studios", "List the available owned Studio.", {})
			add("start_stop_play", "Start Play with is_start=true or stop it with false.", { "is_start" })
			add("screen_capture", "Capture the current Studio viewport.", {}, { "capture_id" })
			add(
				"execute_luau",
				"Execute Luau in Edit, Client, or Server. Return the result. Edit changes persist; Play changes are temporary.",
				{ "code", "datamodel_type" }
			)
			add("get_console_output", "Read this Studio's console output.", {})
			add(
				"input",
				"Execute Luau on Client for native virtual input during Play. "
					.. "local input = game:GetService('UserInputService'):CreateVirtualInput(); "
					.. "input:SendKey(true, Enum.KeyCode.W, false) presses W; false releases it. "
					.. "input:SendMouseButton(Vector2.new(x, y), Enum.UserInputType.MouseButton1, true) presses; false releases. "
					.. "Release held inputs. CoreGUI-reserved keys cannot be injected.",
				{ "code" }
			)
			return { tools = tools }
		end
		assert(method == "tools/call", "unsupported MCP method")
		local request = Schema.record(params, "tool call")
		Schema.only(request, "tool call", { "name", "arguments", "_meta" })
		local name = Schema.text(request.name, "tool call.name")
		local args: Schema.Record = if request.arguments == nil
			then {}
			else Schema.record(request.arguments, "tool call.arguments")
		assert(args.studio_id == nil or args.studio_id == target.id, "the tool call targets another Studio")
		if name == "list_roblox_studios" then
			Schema.only(args, "list arguments", { "studio_id" })
			return text { studios = { { id = target.id, name = target.name } } }
		end
		assert(ALLOWED[name] == true, "tool is outside the run scope")
		local forwarded: { [string]: unknown } = table.clone(args)
		forwarded.studio_id = target.id
		if name == "input" then
			Schema.only(args, "input arguments", { "studio_id", "code" })
			Schema.text(args.code, "input arguments.code")
			forwarded.datamodel_type = "Client"
			return forward("execute_luau", forwarded)
		elseif name == "execute_luau" then
			Schema.only(args, "execute arguments", { "studio_id", "code", "datamodel_type" })
			Schema.text(args.code, "execute arguments.code")
			assert(
				args.datamodel_type == "Edit" or args.datamodel_type == "Client" or args.datamodel_type == "Server",
				"invalid datamodel"
			)
		elseif name == "start_stop_play" then
			Schema.only(args, "play arguments", { "studio_id", "is_start" })
			assert(type(args.is_start) == "boolean", "play requires is_start")
		elseif name == "screen_capture" then
			Schema.only(args, "capture arguments", { "studio_id", "capture_id" })
			forwarded.capture_id = Schema.optionalText(args.capture_id, "capture arguments.capture_id")
				or "verify-agent"
		else
			Schema.only(args, "tool arguments", { "studio_id" })
		end
		return forward(name, forwarded)
	end
	return {
		dispatch = dispatch,
		close = function()
			closed = true
		end,
	}
end

return { create = create }
