--!strict

export type Area = { number }
export type Device = {
	id: string,
	viewport: { number },
	preferredInput: string,
	touch: boolean,
	keyboard: boolean,
	mouse: boolean,
	gamepad: boolean,
	tenFoot: boolean,
	orientation: string?,
	guiInset: { number },
	topbar: Area,
	none: Area,
	coreUI: Area,
	device: Area,
}
type Shape = { viewport: { number }, trim: { number }, notch: { number } }
type Profile = {
	preferredInput: string,
	touch: boolean,
	keyboard: boolean,
	mouse: boolean,
	gamepad: boolean,
	tenFoot: boolean,
	orientation: string?,
	shapes: { [string]: Shape },
}

local INSET, TOPBAR_LEFT = 58, 164

local profiles: { [string]: Profile } = {
	hd_1080 = {
		preferredInput = "KeyboardAndMouse",
		touch = false,
		keyboard = true,
		mouse = true,
		gamepad = false,
		tenFoot = false,
		shapes = { fixed = { viewport = { 1919, 1080 }, trim = { 1, 0 }, notch = { 0, 0, 0, 0 } } },
	},
	iphone_14 = {
		preferredInput = "Touch",
		touch = true,
		keyboard = false,
		mouse = false,
		gamepad = false,
		tenFoot = false,
		orientation = "LandscapeLeft",
		shapes = {
			LandscapeLeft = { viewport = { 749, 389 }, trim = { 95, 1 }, notch = { 47, 0, 47, 0 } },
			LandscapeRight = { viewport = { 749, 389 }, trim = { 95, 1 }, notch = { 47, 0, 47, 0 } },
			Portrait = { viewport = { 389, 762 }, trim = {}, notch = { 0, 47, 0, 34 } },
		},
	},
	xbox = {
		preferredInput = "Gamepad",
		touch = false,
		keyboard = false,
		mouse = false,
		gamepad = true,
		tenFoot = true,
		shapes = { fixed = { viewport = { 1919, 1080 }, trim = { 1, 0 }, notch = { 0, 0, 0, 0 } } },
	},
	generic_handheld_720 = {
		preferredInput = "Gamepad",
		touch = false,
		keyboard = true,
		mouse = true,
		gamepad = true,
		tenFoot = false,
		shapes = { fixed = { viewport = { 1279, 720 }, trim = { 1, 0 }, notch = { 0, 0, 0, 0 } } },
	},
}

local function build(id: string, profile: Profile, shape: Shape, width: number, height: number): Device
	local notch = shape.notch
	return {
		id = id,
		viewport = { width, height },
		preferredInput = profile.preferredInput,
		touch = profile.touch,
		keyboard = profile.keyboard,
		mouse = profile.mouse,
		gamepad = profile.gamepad,
		tenFoot = profile.tenFoot,
		orientation = profile.orientation,
		guiInset = { 0, INSET, 0, 0 },
		topbar = { TOPBAR_LEFT, 0, width, INSET },
		none = { -notch[1], -INSET - notch[2], width + notch[3], height - INSET + notch[4] },
		coreUI = { 0, 0, width, height - INSET },
		device = { 0, -INSET, width, height - INSET },
	}
end

local function unsupported(message: string): never
	error("unsupported_method: StudioDeviceSimulatorService." .. message, 0)
end

local function shapeOf(id: string, orientation: string?): (Profile, Shape)
	local profile = profiles[id]
	if profile == nil then
		unsupported("SetDeviceAsync has no captured device " .. id)
	end
	local shape = profile.shapes[orientation or profile.orientation or "fixed"]
	if shape == nil then
		unsupported(`SetOrientationAsync has no captured {tostring(orientation)} shape for {id}`)
	end
	return profile, shape
end

local function device(id: string): Device
	local profile, shape = shapeOf(id, nil)
	return build(id, profile, shape, shape.viewport[1], shape.viewport[2])
end

local function oriented(current: Device, orientation: string): Device
	local profile = profiles[current.id]
	if profile == nil or profile.orientation == nil then
		error("StudioDeviceSimulatorService: orientation can only be set on mobile (phone or tablet) devices", 0)
	end
	local _, shape = shapeOf(current.id, orientation)
	local result = build(current.id, profile, shape, shape.viewport[1], shape.viewport[2])
	result.orientation = orientation
	return result
end

local function resized(current: Device, width: number, height: number): Device
	local profile, shape = shapeOf(current.id, current.orientation)
	local trim = shape.trim
	if trim[1] == nil then
		unsupported(
			`SetResolutionAsync has no captured resolution rule for {current.id} {tostring(current.orientation)}`
		)
	end
	local result = build(current.id, profile, shape, width - trim[1], height - trim[2])
	result.orientation = current.orientation
	return result
end

local function desktop(width: number, height: number): Device
	return {
		id = "desktop",
		viewport = { width, height },
		preferredInput = "KeyboardAndMouse",
		touch = false,
		keyboard = true,
		mouse = true,
		gamepad = false,
		tenFoot = false,
		guiInset = { 0, 0, 0, 0 },
		topbar = { 0, 0, width, 0 },
		none = { 0, 0, width, height },
		coreUI = { 0, 0, width, height },
		device = { 0, 0, width, height },
	}
end

return { device = device, oriented = oriented, resized = resized, desktop = desktop }
