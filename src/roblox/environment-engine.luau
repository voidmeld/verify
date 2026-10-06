--!strict

local Environment = require "./environment"
local Datatypes = require "./datatypes"

export type Connection = { Disconnect: (Connection) -> () }
export type Signal<A... = ...unknown> = { Connect: (Signal<A...>, (A...) -> ()) -> Connection }
export type Vector2 = { X: number, Y: number }
export type Vector3 = { X: number, Y: number, Z: number }
export type Color3 = { R: number, G: number, B: number }
export type UDim = { Scale: number, Offset: number }
export type UDim2 = { X: UDim, Y: UDim }
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
export type Library<V2 = Vector2, V3 = Vector3, C3 = Color3, U1 = UDim, U2 = UDim2, CF = CFrame> = {
	typeName: (unknown) -> string,
	datatypes: {
		Vector2: { new: (number, number) -> V2 },
		Vector3: { new: (number, number, number) -> V3 },
		Color3: { new: (number, number, number) -> C3 },
		UDim: { new: (number, number) -> U1 },
		UDim2: { new: (number, number, number, number) -> U2 },
		CFrame: { new: (...number) -> CF },
	},
}

local function create<V2, V3, C3, U1, U2, CF>(environment: Environment.Environment, library: Library<V2, V3, C3, U1, U2, CF>?): Engine
	local source: Library = (library :: unknown) :: Library?
		or ({ typeName = Environment.typeName, datatypes = Datatypes } :: unknown) :: Library
	return {
		new = function(className: string): Instance
			return (environment.createInstance(className) :: unknown) :: Instance
		end,
		heartbeat = (environment.heartbeat :: unknown) :: Signal<number>,
		clock = environment.now,
		typeName = source.typeName,
		destroy = function(value: unknown)
			(value :: Environment.Instance):Destroy()
		end,
		propertyChanged = function(value: unknown, property: string): Signal<()>
			return ((value :: Environment.Instance):GetPropertyChangedSignal(property) :: unknown) :: Signal<()>
		end,
		datatypes = {
			Vector2 = source.datatypes.Vector2.new,
			Vector3 = source.datatypes.Vector3.new,
			Color3 = source.datatypes.Color3.new,
			UDim = source.datatypes.UDim.new,
			UDim2 = source.datatypes.UDim2.new,
			CFrame = function(position: Vector3, rotation: { number }): CFrame
				assert(#rotation == 9, "CFrame rotation requires nine components")
				return source.datatypes.CFrame.new(position.X, position.Y, position.Z, table.unpack(rotation, 1, 9))
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
