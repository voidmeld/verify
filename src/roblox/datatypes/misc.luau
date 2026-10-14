--!strict

local Enum = require "./enum"
local Float = require "./float"
local Names = require "./names"
local Udim = require "./udim"

type EnumItem = Enum.EnumItem
type Enums = Enum.Enums
type UDim2Value = Udim.UDim2Value

export type TweenInfoValue = typeof(setmetatable(
	{} :: {
		Time: number,
		EasingStyle: EnumItem,
		EasingDirection: EnumItem,
		RepeatCount: number,
		Reverses: boolean,
		DelayTime: number,
	},
	{} :: { __eq: (TweenInfoValue, TweenInfoValue) -> boolean, __tostring: (TweenInfoValue) -> string }
))

export type ContentValue = typeof(setmetatable(
	{} :: { SourceType: EnumItem, Uri: string?, Object: unknown? },
	{} :: { __eq: (ContentValue, ContentValue) -> boolean, __tostring: (ContentValue) -> string }
))

export type FloatCurveKeyValue = typeof(setmetatable(
	{} :: {
		Time: number,
		Value: number,
		Interpolation: EnumItem,
		LeftTangent: number?,
		RightTangent: number?,
	},
	{} :: { __eq: (FloatCurveKeyValue, FloatCurveKeyValue) -> boolean, __tostring: (FloatCurveKeyValue) -> string }
))

export type Path2DControlPointValue = typeof(setmetatable(
	{} :: { Position: UDim2Value, LeftTangent: UDim2Value, RightTangent: UDim2Value },
	{} :: {
		__eq: (Path2DControlPointValue, Path2DControlPointValue) -> boolean,
		__tostring: (Path2DControlPointValue) -> string,
	}
))

export type TweenInfoConstructor = {
	new: (
		time: number?,
		easingStyle: EnumItem?,
		easingDirection: EnumItem?,
		repeatCount: number?,
		reverses: boolean?,
		delayTime: number?
	) -> TweenInfoValue,
}
export type ContentConstructor = {
	fromUri: (uri: string) -> ContentValue,
	fromAssetId: (id: number | string) -> ContentValue,
	fromObject: (object: unknown) -> ContentValue,
	none: ContentValue,
}
export type FloatCurveKeyConstructor = {
	new: (time: number, value: number, interpolation: EnumItem) -> FloatCurveKeyValue,
}
export type Path2DControlPointConstructor = {
	new: (position: UDim2Value?, leftTangent: UDim2Value?, rightTangent: UDim2Value?) -> Path2DControlPointValue,
}

local TweenInfoKind = Names.behavior("TweenInfo", { quoted = true })
local ContentKind = Names.behavior "Content"
local FloatCurveKeyKind = Names.behavior("FloatCurveKey", { quoted = true })
local Path2DControlPointKind = Names.behavior("Path2DControlPoint", { quoted = true })

local function checkItem(value: unknown, family: string, position: number): EnumItem
	if not Enum.isItem(value) or Enum.enumType(value) ~= family then
		Names.argument(position, "Enum." .. family, value)
	end
	return value :: EnumItem
end

TweenInfoKind.meta.__eq = function(a: TweenInfoValue, b: TweenInfoValue): boolean
	return a.Time == b.Time
		and a.EasingStyle == b.EasingStyle
		and a.EasingDirection == b.EasingDirection
		and a.RepeatCount == b.RepeatCount
		and a.Reverses == b.Reverses
		and a.DelayTime == b.DelayTime
end
TweenInfoKind.meta.__tostring = function(a: TweenInfoValue): string
	return ("Time:%s DelayTime:%s RepeatCount:%d Reverses:%s EasingDirection:%s EasingStyle:%s"):format(
		Float.general(a.Time, 6),
		Float.general(a.DelayTime, 6),
		a.RepeatCount,
		if a.Reverses then "True" else "False",
		a.EasingDirection.Name,
		a.EasingStyle.Name
	)
end

ContentKind.fields.__index = function(_: unknown, key: unknown): unknown
	if key == "Uri" or key == "Object" then
		return nil
	end
	return Names.missing(ContentKind, key)
end
ContentKind.meta.__eq = function(a: ContentValue, b: ContentValue): boolean
	return a.SourceType == b.SourceType and a.Uri == b.Uri and rawequal(a.Object, b.Object)
end
ContentKind.meta.__tostring = function(a: ContentValue): string
	local source = a.SourceType.Name
	if source == "Uri" then
		return ("Content{SourceType=Uri, Uri=%s}"):format(tostring(a.Uri))
	elseif source == "Object" then
		return ("Content{SourceType=Object, Object=%s}"):format(tostring(a.Object))
	end
	return "Content{SourceType=" .. source .. "}"
end

FloatCurveKeyKind.fields.__index = function(_: unknown, key: unknown): unknown
	if key == "LeftTangent" or key == "RightTangent" then
		return nil
	end
	return Names.missing(FloatCurveKeyKind, key)
end
FloatCurveKeyKind.meta.__newindex = function(value: unknown, key: unknown, assigned: unknown)
	if key == "LeftTangent" or key == "RightTangent" then
		if assigned ~= nil and type(assigned) ~= "number" then
			Names.argument(3, "number", assigned)
		end
		Names.fields(value)[key] = if assigned == nil then nil else Float.f32(assigned :: number)
		return
	end
	Names.readOnly(key, "FloatCurveKey")
end
FloatCurveKeyKind.meta.__eq = function(a: FloatCurveKeyValue, b: FloatCurveKeyValue): boolean
	return a.Time == b.Time
		and a.Value == b.Value
		and a.Interpolation == b.Interpolation
		and a.LeftTangent == b.LeftTangent
		and a.RightTangent == b.RightTangent
end
FloatCurveKeyKind.meta.__tostring = function(a: FloatCurveKeyValue): string
	local function optional(value: number?): string
		return if value == nil then "nil" else Float.general(value, 6)
	end
	return ("{%s, %s, %s, %s, %s}"):format(
		a.Interpolation.Name,
		Float.general(a.Time, 6),
		Float.general(a.Value, 6),
		optional(a.LeftTangent),
		optional(a.RightTangent)
	)
end

Path2DControlPointKind.meta.__eq = function(a: Path2DControlPointValue, b: Path2DControlPointValue): boolean
	return a.Position == b.Position and a.LeftTangent == b.LeftTangent and a.RightTangent == b.RightTangent
end
Path2DControlPointKind.meta.__tostring = function(a: Path2DControlPointValue): string
	return ("Path2DControlPoint { Position = %s, LeftTangent = %s, RightTangent = %s }"):format(
		tostring(a.Position),
		tostring(a.LeftTangent),
		tostring(a.RightTangent)
	)
end

local function tweenInfo(enums: Enums): TweenInfoConstructor
	return {
		new = function(
			time: number?,
			easingStyle: EnumItem?,
			easingDirection: EnumItem?,
			repeatCount: number?,
			reverses: boolean?,
			delayTime: number?
		): TweenInfoValue
			return Names.make(TweenInfoKind, {
				Time = Float.f32(Float.coerce(if time == nil then 1 else time, 1)),
				EasingStyle = if easingStyle == nil
					then enums.EasingStyle.Quad
					else checkItem(easingStyle, "EasingStyle", 2),
				EasingDirection = if easingDirection == nil
					then enums.EasingDirection.Out
					else checkItem(easingDirection, "EasingDirection", 3),
				RepeatCount = Float.int32(Float.coerce(repeatCount, 4)),
				Reverses = reverses == true,
				DelayTime = Float.f32(Float.coerce(delayTime, 6)),
			})
		end,
	}
end

local function content(enums: Enums): ContentConstructor
	local function make(source: string, uri: string?, object: unknown?): ContentValue
		return Names.make(ContentKind, { SourceType = enums.ContentSourceType[source], Uri = uri, Object = object })
	end
	local constructor = {
		fromUri = function(uri: string): ContentValue
			if type(uri) ~= "string" then
				Names.argument(1, "string", uri)
			end
			return make("Uri", uri, nil)
		end,
		fromAssetId = function(id: number | string): ContentValue
			return make("Uri", "rbxassetid://" .. tostring(id), nil)
		end,
		fromObject = function(object: unknown): ContentValue
			if object == nil then
				Names.argument(1, "Object", object)
			end
			return make("Object", nil, object)
		end,
	}
	setmetatable(constructor, {
		__index = function(self: { [string]: unknown }, key: unknown): unknown
			if key ~= "none" then
				return nil
			end
			local none = make("None", nil, nil)
			rawset(self, "none", none)
			return none
		end,
	})
	return (constructor :: unknown) :: ContentConstructor
end

local function floatCurveKey(): FloatCurveKeyConstructor
	return {
		new = function(time: number, value: number, interpolation: EnumItem): FloatCurveKeyValue
			return Names.make(FloatCurveKeyKind, {
				Time = Float.f32(Float.coerce(time, 1)),
				Value = Float.f32(Float.coerce(value, 2)),
				Interpolation = checkItem(interpolation, "KeyInterpolationMode", 3),
			})
		end,
	}
end

local function path2DControlPoint(): Path2DControlPointConstructor
	local zero = Udim.UDim2.new(0, 0, 0, 0)
	return {
		new = function(
			position: UDim2Value?,
			leftTangent: UDim2Value?,
			rightTangent: UDim2Value?
		): Path2DControlPointValue
			return Names.make(Path2DControlPointKind, {
				Position = position or zero,
				LeftTangent = leftTangent or zero,
				RightTangent = rightTangent or zero,
			})
		end,
	}
end

return {
	tweenInfo = tweenInfo,
	content = content,
	floatCurveKey = floatCurveKey,
	path2DControlPoint = path2DControlPoint,
}
