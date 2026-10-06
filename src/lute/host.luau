--!strict

local Core = require "../runtime/host"
local Runtime = require "./runtime"
local Verify = require "../core"

export type Options = Core.Options

local DEFAULT_COMMAND = Runtime.defaultCommand
local DEFAULT_DIRECTORY = Runtime.defaultDirectory
local DEFAULT_CAPABILITIES = Core.DEFAULT_CAPABILITIES

local function create(options: Options): Verify.Host
	return Core.create(Runtime, options)
end

return {
	DEFAULT_COMMAND = DEFAULT_COMMAND,
	DEFAULT_DIRECTORY = DEFAULT_DIRECTORY,
	DEFAULT_CAPABILITIES = DEFAULT_CAPABILITIES,
	create = create,
}
