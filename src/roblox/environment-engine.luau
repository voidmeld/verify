--!strict

local Environment = require "./environment"
local Datatypes = require "./datatypes"
local Vm = require "./value"

export type Connection = { Disconnect: (Connection) -> () }
export type Signal<A... = ...unknown> = { Connect: (Signal<A...>, (A...) -> ()) -> Connection }
export type Vector2 = { read X: number, read Y: number }
export type Vector3 = { read X: number, read Y: number, read Z: number }
export type Color3 = { read R: number, read G: number, read B: number }
export type UDim = { read Scale: number, read Offset: number }
export type UDim2 = { read X: UDim, read Y: UDim }
export type CFrame = { GetComponents: (CFrame) -> ...number }
export type Instance = {
	ClassName: string,
	Name: string,
	Parent: unknown,
	Destroy: (Instance) -> (),
	SetAttribute: (Instance, string, unknown) -> (),
	GetPropertyChangedSignal: (Instance, string) -> Signal<()>,
}
export type Engine = {
	new: (string) -> Instance,
	heartbeat: Signal<number>,
	clock: () -> number,
	typeName: (unknown) -> string,
	destroy: (unknown) -> (),
	propertyChanged: (unknown, string) -> Signal<()>,
	datatypes: {
		Vector2: ((number, number) -> Vector2)?,
		Vector3: ((number, number, number) -> Vector3)?,
		Color3: ((number, number, number) -> Color3)?,
		UDim: ((number, number) -> UDim)?,
		UDim2: ((number, number, number, number) -> UDim2)?,
		CFrame: ((Vector3, { number }) -> CFrame)?,
	},
	readCFrame: ((CFrame) -> (number, number, number, { number }))?,
}
export type Library = {
	read typeName: (unknown) -> string,
	read datatypes: {
		read Vector2: { read new: (number, number) -> Datatypes.Vector2Value },
		read Vector3: { read new: (number, number, number) -> Datatypes.Vector3Value },
		read Color3: { read new: (number, number, number) -> Datatypes.Color3Value },
		read UDim: { read new: (number, number) -> Datatypes.UDimValue },
		read UDim2: { read new: (number, number, number, number) -> Datatypes.UDim2Value },
		read CFrame: { read new: (...number) -> Datatypes.CFrameValue },
	},
}

local held: unknown
local lens = {
	__index = function(): unknown
		return held
	end,
}
local instanceSlot: { Instance } = setmetatable({}, lens)
local frameValueSlot: { CFrame } = setmetatable({}, lens)
local signalSlot: { Signal<()> } = setmetatable({}, lens)
local frameSlot: { Signal<number> } = setmetatable({}, lens)

local function callMethod(value: unknown, name: string, ...: unknown): Vm.Value
	local target = Vm.value(value)
	local result = Vm.invoke(Vm.read(target, name), target, ...)
	return result
end

local function create(environment: Environment.Environment, library: Library?): Engine
	local source: Library = library or { typeName = Environment.typeName, datatypes = Datatypes }
	held = environment.heartbeat
	local beats = frameSlot[1]
	held = nil
	return {
		new = function(className: string): Instance
			held = environment.createInstance(className)
			local created = instanceSlot[1]
			held = nil
			return created
		end,
		heartbeat = beats,
		clock = environment.now,
		typeName = source.typeName,
		destroy = function(value: unknown)
			callMethod(value, "Destroy")
		end,
		propertyChanged = function(value: unknown, property: string): Signal<()>
			held = callMethod(value, "GetPropertyChangedSignal", property)
			local signal = signalSlot[1]
			held = nil
			return signal
		end,
		datatypes = {
			Vector2 = source.datatypes.Vector2.new,
			Vector3 = source.datatypes.Vector3.new,
			Color3 = source.datatypes.Color3.new,
			UDim = source.datatypes.UDim.new,
			UDim2 = source.datatypes.UDim2.new,
			CFrame = function(position: Vector3, rotation: { number }): CFrame
				assert(#rotation == 9, "CFrame rotation requires nine components")
				held = source.datatypes.CFrame.new(position.X, position.Y, position.Z, table.unpack(rotation, 1, 9))
				local frame = frameValueSlot[1]
				held = nil
				return frame
			end,
		},
		readCFrame = function(value: CFrame): (number, number, number, { number })
			local components = { value:GetComponents() }
			assert(#components == 12, "CFrame requires twelve components")
			return components[1], components[2], components[3], { table.unpack(components, 4, 12) }
		end,
	}
end

return { create = create }
