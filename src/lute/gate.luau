--!strict

local Gate = require "../runtime/gate"
local Runtime = require "./runtime"

export type Options = Gate.Options

return Gate.create(Runtime)
