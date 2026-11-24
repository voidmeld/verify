--!strict
local Environment = require "./environment"
local Datatypes = require "./datatypes"

type Instance = Environment.Instance
type Point = { X: number, Y: number }
export type Options = {
	service: Instance,
	library: Datatypes.Library,
	createInput: (unknown) -> Instance,
	targets: (Point) -> ({ Instance }, Instance?, { Instance }),
	scroll: ({ Instance }, number, number) -> boolean,
	processed: ({ Instance }, boolean) -> boolean,
	detector: ({ Instance }) -> Instance?,
	dragOffset: (Instance, number, number) -> unknown,
	read: (Instance, string) -> unknown,
	changed: () -> (),
	focus: (Instance?, Instance) -> (),
	toScreen: (Point) -> Point,
	activationWindowSeconds: number,
}

local function create(env: Environment.Environment, options: Options)
	local library, service = options.library, options.service
	local states = library.Enum.UserInputState
	local contact: Instance? = nil
	local previous: Point = { X = 0, Y = 0 }
	local origin: Point = previous
	local hovered: { Instance } = {}
	local pressed: Instance? = nil
	local detector: Instance? = nil
	local scrollHits: { Instance } = {}
	local longTargets: { Instance } = {}
	local longPending, longActive = false, false
	local activations: { [Instance]: { released: number, count: number } } = {}
	do
		local weak = activations
		setmetatable(weak, { __mode = "ks" })
	end
	local function update(object: Instance, at: Point, state: unknown, moving: boolean)
		env.poke(object, "UserInputState", state)
		env.poke(object, "Position", library.Vector3.new(at.X, at.Y, 0))
		env.poke(
			object,
			"Delta",
			if moving
				then library.Vector3.new(at.X - previous.X, at.Y - previous.Y, 0)
				else library.Vector3.new(0, 0, 0)
		)
		previous = at
	end
	local function drag(at: Point, event: string)
		local active = detector
		if active and env.isAlive(active) then
			env.poke(active, "DragUDim2", options.dragOffset(active, at.X - origin.X, at.Y - origin.Y))
			env.fire(active, event, library.Vector2.new(at.X, at.Y))
		end
	end
	local function transition(at: Point, targets: { Instance }, object: Instance, ending: boolean)
		for _, old in hovered do
			if env.isAlive(old) and not table.find(targets, old) then
				env.fire(old, "MouseLeave", at.X, at.Y)
				if not detector or ending then
					env.fire(old, "InputEnded", object)
				end
			end
		end
		for _, target in targets do
			if not table.find(hovered, target) then
				env.fire(target, "MouseEnter", at.X, at.Y)
				env.fire(target, "InputBegan", object)
			elseif not detector then
				env.fire(target, "InputChanged", object)
			end
		end
		hovered = targets
	end
	local function longPress(at: Point, state: unknown)
		local screen = options.toScreen(at)
		local points = { library.Vector2.new(screen.X, screen.Y) }
		for _, target in longTargets do
			if env.isAlive(target) then
				env.fire(target, "TouchLongPress", points, state)
			end
		end
		env.fire(
			service,
			"TouchLongPress",
			{ library.Vector2.new(at.X, at.Y) },
			state,
			options.processed(longTargets, true)
		)
	end
	return {
		move = function(at: Point)
			local object = contact
			if not object or at.X == previous.X and at.Y == previous.Y then
				return
			end
			local targets = options.targets(at)
			local dx, dy = at.X - origin.X, at.Y - origin.Y
			if dx * dx + dy * dy >= 25 then
				longPending = false
			end
			if not detector and options.scroll(scrollHits, previous.X - at.X, previous.Y - at.Y) then
				pressed = nil
			end
			update(object, at, states.Change, true)
			drag(at, "DragContinue")
			transition(at, targets, object, false)
			if longActive then
				longPress(at, states.Change)
			end
			local consumed = detector ~= nil or options.processed(targets, true)
			env.fire(service, "InputChanged", object, consumed)
			env.fire(service, "TouchMoved", object, consumed)
		end,
		press = function(at: Point, down: boolean)
			assert(down == (contact == nil), "VirtualInput::SendMouseButton: duplicate button state.")
			local targets, targetButton, objects = options.targets(at)
			local object = contact or options.createInput(library.Enum.UserInputType.Touch)
			update(object, at, if down then states.Begin else states.End, false)
			options.changed()
			if down then
				contact, origin, pressed = object, at, targetButton
				longTargets, longPending, longActive = targets, true, false
				env.scheduler.delay(0.5, function()
					if contact == object and longPending then
						longPending, longActive = false, true
						longPress(previous, states.Begin)
					end
				end)
				scrollHits = objects
				detector = options.detector(targets)
				if detector then
					pressed = nil
					drag(at, "DragStart")
				elseif targetButton then
					env.fire(targetButton, "MouseButton1Down", at.X, at.Y)
				end
				transition(at, targets, object, false)
				options.focus(targets[1], object)
				local consumed = detector ~= nil or options.processed(targets, true)
				env.fire(service, "InputBegan", object, consumed)
				env.fire(service, "TouchStarted", object, consumed)
			else
				local consumed = detector ~= nil or options.processed(targets, true)
				longPending = false
				if longActive then
					longActive = false
					longPress(at, states.End)
				end
				drag(at, "DragEnd")
				if pressed and env.isAlive(pressed) and pressed == targetButton then
					env.fire(pressed, "MouseButton1Up", at.X, at.Y)
					if options.read(pressed, "Active") == true then
						local prior = activations[pressed]
						local released = env.now()
						local count = if prior and released - prior.released < options.activationWindowSeconds
							then prior.count + 1
							else 0
						activations[pressed] = { released = released, count = count }
						env.fire(pressed, "Activated", object, count)
					end
					env.fire(pressed, "MouseButton1Click")
				end
				transition(at, {}, object, true)
				env.fire(service, "InputEnded", object, consumed)
				env.fire(service, "TouchEnded", object, consumed)
				contact, detector, pressed = nil, nil, nil
				table.clear(scrollHits)
				table.clear(longTargets)
			end
		end,
		close = function()
			longPending, longActive = false, false
			if contact then
				env.poke(contact, "UserInputState", states.Cancel)
			end
			contact, detector, pressed = nil, nil, nil
			table.clear(hovered)
			table.clear(scrollHits)
			table.clear(longTargets)
			table.clear(activations)
		end,
	}
end

return { create = create }
