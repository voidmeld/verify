--!strict
local Environment = require "./environment"
local Datatypes = require "./datatypes"
local Values = require "./ui-values"

type Instance = Environment.Instance
type Point = { X: number, Y: number }
type Motion = { origin: Point, target: Point, last: Point, started: number? }
export type Controller = {
	send: (Point, { [string]: unknown }) -> boolean,
	drag: ({ Instance }, number, number) -> boolean,
	step: () -> (),
	close: () -> (),
}
export type Options = {
	service: Instance,
	library: Datatypes.Library,
	input: (unknown) -> Instance,
	hits: (Point) -> { Instance },
	inset: () -> Point,
	read: (Instance, string) -> unknown,
	changed: () -> (),
}

local function create(env: Environment.Environment, options: Options): Controller
	local library, read = options.library, options.read
	local motions: { [Instance]: Motion } = {}
	local wheelInput: Instance? = nil
	local function number(value: unknown): number
		if value == nil then
			return 0
		end
		assert(
			type(value) == "number" and value == value and math.abs(value) < math.huge,
			"pointer actions require finite numbers"
		)
		return value
	end
	local function scroll(objects: { Instance }, x: number, y: number, touch: boolean): boolean
		local consumed = false
		local planned: { [Instance]: Motion } = {}
		local current: Instance? = nil
		for _, object in objects do
			if
				object:IsA "ScrollingFrame"
				or read(object, "Active") == true
					and (object.ClassName ~= "Frame" or touch and Values.enumName(
						read(object, "InputSink"),
						"InputSink"
					) == "All")
			then
				current = object
				break
			end
		end
		while current and (x ~= 0 or y ~= 0) do
			if current:IsA "ScrollingFrame" and read(current, "ScrollingEnabled") ~= false then
				local canvas = Values.vector(read(current, "AbsoluteCanvasSize"))
				local window = Values.vector(read(current, "AbsoluteWindowSize"))
				local position = Values.vector(read(current, "CanvasPosition"))
				local active = motions[current]
				local target = if active then active.target else position
				local direction = Values.enumName(read(current, "ScrollingDirection"), "ScrollingDirection")
				local nextX = if direction ~= "Y"
					then math.clamp(target.X + x, 0, math.max(0, canvas.X - window.X))
					else target.X
				local nextY = if direction ~= "X"
					then math.clamp(target.Y + y, 0, math.max(0, canvas.Y - window.Y))
					else target.Y
				local extent = Values.vector(read(current, "AbsoluteSize"))
				if
					Values.enumName(read(current, "VerticalScrollBarInset"), "ScrollBarInset") == "None"
						and nextX > math.max(0, canvas.X - extent.X)
					or Values.enumName(read(current, "HorizontalScrollBarInset"), "ScrollBarInset") == "None"
						and nextY > math.max(0, canvas.Y - extent.Y)
				then
					error("unsupported_simulated_input: pointer scrolling beyond the authored layout clamp", 0)
				end
				if nextX ~= target.X or nextY ~= target.Y then
					planned[current] = { origin = position, target = { X = nextX, Y = nextY }, last = position }
					if nextX ~= target.X then
						x = 0
					end
					if nextY ~= target.Y then
						y = 0
					end
					consumed = true
				end
			end
			current = current.Parent
		end
		for object, motion in planned do
			if touch then
				motions[object] = nil
				env.poke(object, "CanvasPosition", library.Vector2.new(motion.target.X, motion.target.Y))
			else
				motions[object] = motion
			end
		end
		return consumed
	end
	return {
		drag = function(objects: { Instance }, x: number, y: number): boolean
			return scroll(objects, x, y, true)
		end,
		send = function(at: Point, action: { [string]: unknown }): boolean
			for key in action do
				assert(key == "Wheel" or key == "Pan" or key == "Pinch", "unknown pointer action")
			end
			local wheel, pinch = number(action.Wheel), number(action.Pinch)
			local pan = if action.Pan ~= nil then Values.vector(action.Pan) else { X = 0, Y = 0 }
			number(pan.X)
			number(pan.Y)
			if wheel == 0 and pinch == 0 and pan.X == 0 and pan.Y == 0 then
				return false
			end
			assert(
				(if wheel ~= 0 then 1 else 0)
						+ (if pinch ~= 0 then 1 else 0)
						+ (if pan.X ~= 0 or pan.Y ~= 0 then 1 else 0)
					== 1,
				"unsupported_simulated_input: combined pointer actions"
			)
			local objects = options.hits(at)
			local consumed = scroll(objects, -pan.X * 100 / 30, -(wheel + pinch) * 100 - pan.Y * 100 / 30, false)
			options.changed()
			local object = wheelInput or options.input(library.Enum.UserInputType.MouseWheel)
			wheelInput = object
			local inset = options.inset()
			env.publish(object, "UserInputState", library.Enum.UserInputState.Change)
			env.publish(object, "Position", library.Vector3.new(at.X - inset.X, at.Y - inset.Y, wheel + pinch + pan.Y))
			env.publish(object, "Delta", library.Vector3.zero)
			for _, target in objects do
				env.fire(target, "InputChanged", object)
				if target:IsA "GuiButton" then
					break
				end
			end
			env.fire(options.service, "InputChanged", object, consumed)
			env.fire(
				options.service,
				"PointerAction",
				wheel,
				library.Vector2.new(pan.X * 2.5, pan.Y * 2.5),
				pinch,
				consumed
			)
			return true
		end,
		step = function()
			for object, motion in motions do
				if not env.isAlive(object) or read(object, "ScrollingEnabled") == false then
					motions[object] = nil
					continue
				end
				local position = Values.vector(read(object, "CanvasPosition"))
				if position.X ~= motion.last.X or position.Y ~= motion.last.Y then
					motions[object] = nil
					continue
				end
				local started = motion.started or env.now()
				motion.started = started
				local time = (env.now() - started) * math.sqrt(800)
				local remaining = (1 + time) * math.exp(-time)
				if remaining < 0.00001 then
					remaining = 0
					motions[object] = nil
				end
				local value = library.Vector2.new(
					motion.target.X + (motion.origin.X - motion.target.X) * remaining,
					motion.target.Y + (motion.origin.Y - motion.target.Y) * remaining
				)
				motion.last = Values.vector(value)
				env.poke(object, "CanvasPosition", value)
			end
		end,
		close = function()
			table.clear(motions)
		end,
	}
end

return { create = create }
