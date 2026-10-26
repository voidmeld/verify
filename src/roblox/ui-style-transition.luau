--!strict

local Datatypes = require "./datatypes"
local Names = require "./datatypes/names"
local Frames = require "./datatypes/cframe"
local Values = require "./ui-values"

export type Timing = { time: number, delay: number, style: string, direction: string }
export type Motion = { target: unknown, origin: unknown, started: number, timing: Timing? }

local function bounce(t: number): number
	if t < 1 / 2.75 then
		return 7.5625 * t * t
	elseif t < 2 / 2.75 then
		t -= 1.5 / 2.75
		return 7.5625 * t * t + 0.75
	elseif t < 2.5 / 2.75 then
		t -= 2.25 / 2.75
		return 7.5625 * t * t + 0.9375
	end
	t -= 2.625 / 2.75
	return 7.5625 * t * t + 0.984375
end

local function inward(t: number, style: string): number
	if style == "Linear" then
		return t
	elseif style == "Sine" then
		return 1 - math.cos(t * math.pi / 2)
	elseif style == "Quad" then
		return t * t
	elseif style == "Cubic" then
		return t ^ 3
	elseif style == "Quart" then
		return t ^ 4
	elseif style == "Quint" then
		return t ^ 5
	elseif style == "Exponential" then
		return 2 ^ (10 * (t - 1))
	elseif style == "Circular" then
		return 1 - math.sqrt(1 - t * t)
	elseif style == "Back" then
		return t * t * (2.70158 * t - 1.70158)
	elseif style == "Bounce" then
		return 1 - bounce(1 - t)
	elseif style == "Elastic" then
		return -(2 ^ (10 * (t - 1))) * math.sin((t - 1.075) * 2 * math.pi / 0.3)
	end
	error("unsupported_ui_style: unknown transition easing style " .. style, 0)
end

local function ease(t: number, style: string, direction: string): number
	if t <= 0 then
		return 0
	elseif t >= 1 then
		return 1
	elseif direction == "In" then
		return inward(t, style)
	elseif direction == "Out" then
		return 1 - inward(1 - t, style)
	end
	assert(direction == "InOut", "unsupported_ui_style: unknown transition easing direction " .. direction)
	if style == "Back" then
		local s = 1.70158 * 1.525
		local x = if t < 0.5 then 2 * t else 2 * t - 2
		return if t < 0.5 then x * x * ((s + 1) * x - s) / 2 else (x * x * ((s + 1) * x + s) + 2) / 2
	elseif style == "Elastic" then
		local x = 2 * t - 1
		return if t < 0.5
			then -0.5 * 2 ^ (10 * x) * math.sin((x - 0.1125) * 2 * math.pi / 0.45)
			else 1 + 0.5 * 2 ^ (-10 * x) * math.sin((x - 0.1125) * 2 * math.pi / 0.45)
	end
	return if t < 0.5 then inward(2 * t, style) / 2 else 1 - inward(2 - 2 * t, style) / 2
end

local function timing(value: unknown): Timing?
	if value == nil then
		return nil
	end
	assert(Names.kind(value) == "TweenInfo", "unsupported_ui_style: transition requires TweenInfo or a TweenInfo token")
	local fields = Names.fields(value)
	local duration, delay = Values.number(fields.Time), Values.number(fields.DelayTime)
	assert(
		duration >= 0 and duration < math.huge,
		"unsupported_ui_style: transition duration must be finite and nonnegative"
	)
	assert(delay >= 0 and delay < math.huge, "unsupported_ui_style: transition delay must be finite and nonnegative")
	return {
		time = duration,
		delay = delay,
		style = Values.enumName(fields.EasingStyle, "EasingStyle"),
		direction = Values.enumName(fields.EasingDirection, "EasingDirection"),
	}
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function interpolate(a: unknown, b: unknown, t: number): unknown
	local kind = Names.kind(a)
	if kind ~= Names.kind(b) then
		return b
	elseif type(a) == "number" and type(b) == "number" then
		return lerp(a, b, t)
	elseif kind == "boolean" or kind == "EnumItem" then
		return if t < 0.5 then a else b
	elseif kind == "CFrame" then
		return Frames.expect(a, 1):Lerp(Frames.expect(b, 2), t)
	end
	local left, right = Names.fields(a), Names.fields(b)
	local function component(key: string): number
		return lerp(Values.number(left[key]), Values.number(right[key]), t)
	end
	if kind == "Color3" then
		return Datatypes.Color3.new(component "R", component "G", component "B")
	elseif kind == "Vector2" then
		return Datatypes.Vector2.new(component "X", component "Y")
	elseif kind == "Vector2int16" then
		return Datatypes.Vector2int16.new(component "X", component "Y")
	elseif kind == "Vector3" then
		return Datatypes.Vector3.new(component "X", component "Y", component "Z")
	elseif kind == "UDim" then
		return Datatypes.UDim.new(component "Scale", math.round(component "Offset"))
	elseif kind == "UDim2" then
		local x = Values.dimension(interpolate(left.X, right.X, t))
		local y = Values.dimension(interpolate(left.Y, right.Y, t))
		return Datatypes.UDim2.new(x.Scale, x.Offset, y.Scale, y.Offset)
	elseif kind == "Rect" then
		local minimum = Values.vector(interpolate(left.Min, right.Min, t))
		local maximum = Values.vector(interpolate(left.Max, right.Max, t))
		return Datatypes.Rect.new(minimum.X, minimum.Y, maximum.X, maximum.Y)
	end
	return b
end

local INTERPOLATED = {
	number = true,
	boolean = true,
	EnumItem = true,
	CFrame = true,
	Color3 = true,
	Vector2 = true,
	Vector2int16 = true,
	Vector3 = true,
	UDim = true,
	UDim2 = true,
	Rect = true,
}

local function sample(motion: Motion, now: number): unknown
	local parameters = motion.timing
	if parameters == nil then
		return motion.target
	end
	local elapsed = now - motion.started - parameters.delay
	if elapsed < 0 then
		return motion.origin
	elseif elapsed >= parameters.time then
		return motion.target
	end
	return interpolate(
		motion.origin,
		motion.target,
		ease(elapsed / parameters.time, parameters.style, parameters.direction)
	)
end

local function retarget(motion: Motion, target: unknown, parameters: Timing?, now: number)
	if target == motion.target then
		if parameters == nil or parameters.time == 0 and parameters.delay == 0 then
			motion.timing = nil
		end
		return
	end
	local origin = sample(motion, now)
	local kind = Names.kind(target)
	motion.origin, motion.target, motion.started = origin, target, now
	motion.timing = if Names.kind(origin) == kind and INTERPOLATED[kind] then parameters else nil
end

return { timing = timing, sample = sample, retarget = retarget, ease = ease }
