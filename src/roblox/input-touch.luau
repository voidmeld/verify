--!strict
local Environment = require "./environment"
local Datatypes = require "./datatypes"

type Instance = Environment.Instance
type Point = { X: number, Y: number }
export type Options = {
	service: Instance,
	library: Datatypes.Library,
	createInput: (unknown) -> Instance,
	targets: (Point) -> ({ Instance }, Instance?),
	processed: ({ Instance }, boolean) -> boolean,
	detector: ({ Instance }) -> Instance?,
	read: (Instance, string) -> unknown,
	changed: () -> (),
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
	local activations: { [Instance]: { released: number, count: number } } = {}
	do
		local weak = activations
		setmetatable(weak, { __mode = "k" })
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
			env.poke(active, "DragUDim2", library.UDim2.fromOffset(at.X - origin.X, at.Y - origin.Y))
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
	return {
		move = function(at: Point)
			local object = contact
			if not object or at.X == previous.X and at.Y == previous.Y then
				return
			end
			local targets = options.targets(at)
			update(object, at, states.Change, true)
			drag(at, "DragContinue")
			transition(at, targets, object, false)
			local consumed = detector ~= nil or options.processed(targets, true)
			env.fire(service, "InputChanged", object, consumed)
			env.fire(service, "TouchMoved", object, consumed)
		end,
		press = function(at: Point, down: boolean)
			assert(down == (contact == nil), "VirtualInput::SendMouseButton: duplicate button state.")
			local targets, targetButton = options.targets(at)
			local object = contact or options.createInput(library.Enum.UserInputType.Touch)
			update(object, at, if down then states.Begin else states.End, false)
			options.changed()
			if down then
				contact, origin, pressed = object, at, targetButton
				detector = options.detector(targets)
				if detector then
					pressed = nil
					drag(at, "DragStart")
				elseif targetButton then
					env.fire(targetButton, "MouseButton1Down", at.X, at.Y)
				end
				transition(at, targets, object, false)
				local consumed = detector ~= nil or options.processed(targets, true)
				env.fire(service, "InputBegan", object, consumed)
				env.fire(service, "TouchStarted", object, consumed)
			else
				local consumed = detector ~= nil or options.processed(targets, true)
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
			end
		end,
		close = function()
			if contact then
				env.poke(contact, "UserInputState", states.Cancel)
			end
			contact, detector, pressed = nil, nil, nil
			table.clear(hovered)
			table.clear(activations)
		end,
	}
end

return { create = create }
