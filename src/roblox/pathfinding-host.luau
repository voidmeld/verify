--!strict

local Types = require "./place-types"
local Vectors = require "./datatypes/vector"

type Vector = Vectors.Vector3Value
export type Compute = (origin: Vector, destination: Vector, parameters: unknown) -> { Vector }?
type Waypoint = { Position: Vector, Action: unknown, Label: string }

local function finite(point: Vector)
	for _, value in { point.X, point.Y, point.Z } do
		assert(value == value and math.abs(value) < math.huge, "path coordinates must be finite")
	end
end

local function install(engine: Types.Engine, compute: Compute)
	local environment = engine.environment
	local paths: { [Types.Instance]: { parameters: unknown, waypoints: { Waypoint } } } = {}
	setmetatable(paths, { __mode = "k" })
	environment.fake(
		"PathfindingService.CreatePath",
		function(_service: Types.Instance, parameters: unknown): Types.Instance
			assert(parameters == nil or type(parameters) == "table", "path parameters must be a table")
			local path = engine.newInstance("Path", true)
			paths[path] =
				{ parameters = if type(parameters) == "table" then table.clone(parameters) else {}, waypoints = {} }
			environment.poke(path, "Status", engine.datatypes.Enum.PathStatus.NoPath)
			return path
		end
	)
	environment.fake("Path.ComputeAsync", function(path: Types.Instance, rawOrigin: unknown, rawDestination: unknown)
		local state = assert(paths[path], "path has no configured computation host")
		local origin, destination = Vectors.expect3(rawOrigin, 1), Vectors.expect3(rawDestination, 2)
		finite(origin)
		finite(destination)
		state.waypoints = {}
		environment.poke(path, "Status", engine.datatypes.Enum.PathStatus.NoPath)
		local points = compute(origin, destination, state.parameters)
		if points == nil then
			return
		end
		assert(#points >= 2, "configured path requires origin and destination")
		assert(points[1] == origin and points[#points] == destination, "configured path endpoints do not match")
		local waypoints: { Waypoint } = {}
		for _, point in points do
			finite(point)
			table.insert(
				waypoints,
				{ Position = point, Action = engine.datatypes.Enum.PathWaypointAction.Walk, Label = "" }
			)
		end
		state.waypoints = waypoints
		environment.poke(path, "Status", engine.datatypes.Enum.PathStatus.Success)
	end)
	environment.fake("Path.GetWaypoints", function(path: Types.Instance): { Waypoint }
		local state = assert(paths[path], "path has no configured computation host")
		local result: { Waypoint } = {}
		for _, waypoint in state.waypoints do
			table.insert(result, table.clone(waypoint))
		end
		return result
	end)
end

return { install = install }
