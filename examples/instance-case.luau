--!strict

local Verify = require "../src/core"
local Roblox = require "../src/roblox"
local Instances = Roblox.instanceHost

local visible = Instances.property(function(value: unknown): boolean
	assert(type(value) == "boolean", "Visible must be boolean")
	return value
end)
local progress = Instances.attribute(function(value: unknown): number
	assert(type(value) == "number", "progress must be numeric")
	return value
end)
local case: Verify.NamedCase = {
	id = "instance-state",
	name = "state and hierarchy changes remain observable",
	timeoutSeconds = 5,
	requires = {
		"action:instance.create",
		"action:instance.setProperty",
		"action:instance.setAttribute",
		"action:instance.parent",
		"query:instance.property",
		"query:instance.attribute",
		"query:instance.inspect",
	},
	run = function(context: Verify.Context)
		context:perform("server", Instances.create, { id = "root", className = "Folder" })
		context:perform("server", Instances.create, { id = "panel", className = "Frame", parent = "root" })
		context:expect(context:perform("server", visible, { id = "panel", key = "Visible" })):toBe(true)
		context:perform("server", Instances.setProperty, { id = "panel", key = "Visible", value = false })
		context:expect(context:perform("server", visible, { id = "panel", key = "Visible" })):toBe(false)
		context:perform("server", Instances.setAttribute, { id = "panel", key = "progress", value = 2 })
		context:expect(context:perform("server", progress, { id = "panel", key = "progress" })):toBe(2)
		context:expect(context:perform("server", Instances.inspect, "root").children):toEqual { "panel" }
		context:perform("server", Instances.parent, { id = "panel" })
		context:expect(context:perform("server", Instances.inspect, "root").children):toEqual {}
	end,
}

return case
