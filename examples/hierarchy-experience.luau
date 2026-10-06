--!strict

local Verify = require "../src/core"
local Experience = require "../src/core/operations"

export type Folder = {
	Name: string,
	Parent: Folder?,
	GetChildren: (self: Folder) -> { Folder },
	IsDescendantOf: (self: Folder, ancestor: Folder) -> boolean,
	Destroy: (self: Folder) -> (),
}
export type Metadata = { name: string, environment: { [string]: string }, now: () -> number }
export type View = { children: { string }, parent: string?, ancestors: { string } }

export type Reparent = { object: string, parent: string? }
local reparent = Verify.operation {
	kind = "action",
	name = "reparent",
	input = function(value: unknown): Reparent
		assert(type(value) == "table", "expected reparent payload")
		local row = value :: { [string]: unknown }
		assert(
			type(row.object) == "string" and (row.parent == nil or type(row.parent) == "string"),
			"invalid reparent payload"
		)
		return { object = row.object :: string, parent = row.parent :: string? }
	end,
	output = function(value: unknown): nil
		assert(value == nil, "reparent returns no value")
		return nil
	end,
}
local children = Verify.operation {
	kind = "query",
	name = "children",
	input = function(value: unknown): string
		assert(type(value) == "string", "expected name")
		return value
	end,
	output = function(value: unknown): View
		assert(type(value) == "table", "expected hierarchy view")
		local row = value :: { [string]: unknown }
		assert(row.parent == nil or type(row.parent) == "string", "invalid parent")
		local function strings(value: unknown): { string }
			assert(type(value) == "table", "expected names")
			local result: { string } = {}
			for index, child in value :: { unknown } do
				assert(index == #result + 1 and type(child) == "string", "invalid name array")
				table.insert(result, child :: string)
			end
			return result
		end
		return { parent = row.parent :: string?, children = strings(row.children), ancestors = strings(row.ancestors) }
	end,
}

local function host(createFolder: () -> Folder, metadata: Metadata): Experience.Host
	local objects: { Folder } = {}
	local folders: { [string]: Folder } = {}
	local initialized = false
	local closed = false

	local function initialize()
		if initialized then
			return
		end
		for _, name in { "root", "previous", "destination", "branch", "leaf" } do
			local folder = createFolder()
			table.insert(objects, folder)
			folder.Name = name
			folders[name] = folder
		end
		folders.previous.Parent = folders.root
		folders.destination.Parent = folders.root
		folders.branch.Parent = folders.previous
		folders.leaf.Parent = folders.branch
		initialized = true
	end

	return {
		name = metadata.name,
		capabilities = { "action:reparent", "query:children" },
		environment = table.clone(metadata.environment),
		now = metadata.now,
		invoke = function(request: Experience.Request): unknown
			assert(not closed, "hierarchy host is closed")
			assert(request.actor == "fixture", "unknown hierarchy actor")
			initialize()
			if request.kind == "action" and request.name == "reparent" then
				assert(type(request.payload) == "table", "reparent requires a named object and parent")
				local payload = request.payload :: { [string]: unknown }
				assert(type(payload.object) == "string", "reparent object must be a name")
				local object = folders[payload.object :: string]
				assert(object ~= nil, "unknown hierarchy object")
				local parent: Folder? = nil
				if payload.parent ~= nil then
					assert(type(payload.parent) == "string", "reparent parent must be a name or nil")
					parent = folders[payload.parent :: string]
					assert(parent ~= nil, "unknown hierarchy parent")
				end
				object.Parent = parent
				return nil
			elseif request.kind == "query" and request.name == "children" then
				assert(type(request.payload) == "string", "children requires an object name")
				local object = folders[request.payload :: string]
				assert(object ~= nil, "unknown hierarchy object")
				local children: { string } = {}
				for _, child in object:GetChildren() do
					table.insert(children, child.Name)
				end
				local ancestors: { string } = {}
				for name, candidate in folders do
					if object:IsDescendantOf(candidate) then
						table.insert(ancestors, name)
					end
				end
				table.sort(children)
				table.sort(ancestors)
				local parent = object.Parent
				local view: View =
					{ children = children, parent = if parent ~= nil then parent.Name else nil, ancestors = ancestors }
				return view
			end
			error("unsupported hierarchy operation", 0)
		end,
		close = function()
			if closed then
				return
			end
			closed = true
			local failures: { string } = {}
			for index = #objects, 1, -1 do
				local object = objects[index]
				local ok, message = pcall(function()
					object:Destroy()
				end)
				if not ok then
					table.insert(failures, tostring(message))
				end
			end
			assert(#failures == 0, "hierarchy cleanup failed: " .. table.concat(failures, "; "))
		end,
	}
end

local case: Verify.NamedCase = {
	id = "hierarchy-reparenting",
	name = "hierarchy preserves subtree identity through reparenting",
	requires = { "action:reparent", "query:children" },
	timeoutSeconds = 5,
	run = function(context: Verify.Context)
		local function view(name: string): View
			return context:perform("fixture", children, name)
		end
		context:expect(view("previous").children):toEqual { "branch" }
		context:expect(view("destination").children):toEqual {}
		context:perform("fixture", reparent, { object = "branch", parent = "destination" })
		context:expect(view("previous").children):toEqual {}
		local destination = view "destination"
		context:expect(destination.children):toEqual { "branch" }
		local branch = view "branch"
		context:expect(branch.parent):toEqual "destination"
		context:expect(branch.children):toEqual { "leaf" }
		local leaf = view "leaf"
		context:expect(leaf.parent):toEqual "branch"
		context:expect(leaf.ancestors):toEqual { "branch", "destination", "root" }
		context:perform("fixture", reparent, { object = "branch" })
		context:expect(view("destination").children):toEqual {}
		local detached = view "branch"
		context:expect(detached.parent):toEqual(nil)
		context:expect(detached.children):toEqual { "leaf" }
		context:expect(view("leaf").ancestors):toEqual { "branch" }
	end,
}

return { case = case, host = host }
