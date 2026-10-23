--!strict

local CFrame = require "@self/cframe"
local Color = require "@self/color"
local Enum = require "@self/enum"
local Font = require "@self/font"
local Misc = require "@self/misc"
local Names = require "@self/names"
local Query = require "@self/query"
local Random = require "@self/random"
local Sequence = require "@self/sequence"
local Spatial = require "@self/spatial"
local Udim = require "@self/udim"
local Vector = require "@self/vector"

export type Vector2Value = Vector.Vector2Value
export type Vector3Value = Vector.Vector3Value
export type Vector2int16Value = Vector.Vector2int16Value
export type Vector3int16Value = Vector.Vector3int16Value
export type CFrameValue = CFrame.CFrameValue
export type RayValue = Spatial.RayValue
export type Region3Value = Spatial.Region3Value
export type RaycastParamsValue = Query.RaycastParamsValue
export type RandomValue = Random.RandomValue
export type OverlapParamsValue = Query.OverlapParamsValue
export type Color3Value = Color.Color3Value
export type BrickColorValue = Color.BrickColorValue
export type UDimValue = Udim.UDimValue
export type UDim2Value = Udim.UDim2Value
export type RectValue = Udim.RectValue
export type NumberRangeValue = Sequence.NumberRangeValue
export type NumberSequenceValue = Sequence.NumberSequenceValue
export type NumberSequenceKeypointValue = Sequence.NumberSequenceKeypointValue
export type ColorSequenceValue = Sequence.ColorSequenceValue
export type ColorSequenceKeypointValue = Sequence.ColorSequenceKeypointValue
export type FontValue = Font.FontValue
export type TweenInfoValue = Misc.TweenInfoValue
export type ContentValue = Misc.ContentValue
export type FloatCurveKeyValue = Misc.FloatCurveKeyValue
export type Path2DControlPointValue = Misc.Path2DControlPointValue
export type EnumMember = Enum.EnumItem
export type EnumCategory = Enum.EnumFamily
export type EnumValue = Enum.Enums
export type EnumCatalog = Enum.Catalog
export type BrickColorCatalog = Color.BrickColorCatalog
export type FontCatalog = Font.FontCatalog

export type Catalog = {
	enums: EnumCatalog?,
	brickColors: BrickColorCatalog?,
	fonts: FontCatalog?,
}

export type Library = {
	Vector2: typeof(Vector.Vector2),
	Vector3: typeof(Vector.Vector3),
	Vector2int16: typeof(Vector.Vector2int16),
	Vector3int16: typeof(Vector.Vector3int16),
	CFrame: typeof(CFrame.CFrame),
	Ray: typeof(Spatial.Ray),
	Region3: typeof(Spatial.Region3),
	RaycastParams: Query.RaycastParamsConstructor,
	Random: typeof(Random),
	OverlapParams: Query.OverlapParamsConstructor,
	Color3: typeof(Color.Color3),
	BrickColor: Color.BrickColorConstructor,
	UDim: typeof(Udim.UDim),
	UDim2: typeof(Udim.UDim2),
	Rect: typeof(Udim.Rect),
	NumberRange: typeof(Sequence.NumberRange),
	NumberSequence: typeof(Sequence.NumberSequence),
	NumberSequenceKeypoint: typeof(Sequence.NumberSequenceKeypoint),
	ColorSequence: typeof(Sequence.ColorSequence),
	ColorSequenceKeypoint: typeof(Sequence.ColorSequenceKeypoint),
	Enum: EnumValue,
	Font: Font.FontConstructor,
	TweenInfo: Misc.TweenInfoConstructor,
	Content: Misc.ContentConstructor,
	FloatCurveKey: Misc.FloatCurveKeyConstructor,
	Path2DControlPoint: Misc.Path2DControlPointConstructor,
	typeName: (value: unknown) -> string?,
	typeof: (value: unknown) -> string,
	enumType: (value: unknown) -> string,
	isAttributeType: (name: string) -> boolean,
	readCFrame: (value: CFrameValue) -> (number, number, number, { number }),
}

local ATTRIBUTE_TYPES: { [string]: boolean } = {
	Vector2 = true,
	Vector3 = true,
	Color3 = true,
	UDim = true,
	UDim2 = true,
	CFrame = true,
	NumberRange = true,
	NumberSequence = true,
	ColorSequence = true,
	Rect = true,
	TweenInfo = true,
	EnumItem = true,
	BrickColor = true,
	Font = true,
	Instance = true,
}

local function isAttributeType(name: string): boolean
	return ATTRIBUTE_TYPES[name] == true
end

local function create(catalog: Catalog?): Library
	local source: Catalog = catalog or {}
	local enums = if source.enums ~= nil then Enum.catalog(source.enums) else Enum.lazy()
	return {
		Vector2 = Vector.Vector2,
		Vector3 = Vector.Vector3,
		Vector2int16 = Vector.Vector2int16,
		Vector3int16 = Vector.Vector3int16,
		CFrame = CFrame.CFrame,
		Ray = Spatial.Ray,
		Region3 = Spatial.Region3,
		RaycastParams = Query.raycast(enums),
		Random = Random,
		OverlapParams = Query.overlap(enums),
		Color3 = Color.Color3,
		BrickColor = Color.brickColor(source.brickColors),
		UDim = Udim.UDim,
		UDim2 = Udim.UDim2,
		Rect = Udim.Rect,
		NumberRange = Sequence.NumberRange,
		NumberSequence = Sequence.NumberSequence,
		NumberSequenceKeypoint = Sequence.NumberSequenceKeypoint,
		ColorSequence = Sequence.ColorSequence,
		ColorSequenceKeypoint = Sequence.ColorSequenceKeypoint,
		Enum = enums,
		Font = Font.constructor(enums, source.fonts),
		TweenInfo = Misc.tweenInfo(enums),
		Content = Misc.content(enums),
		FloatCurveKey = Misc.floatCurveKey(),
		Path2DControlPoint = Misc.path2DControlPoint(),
		typeName = Names.of,
		typeof = Names.kind,
		enumType = Enum.enumType,
		isAttributeType = isAttributeType,
		readCFrame = CFrame.read,
	}
end

local library = create()

return {
	create = create,
	Vector2 = library.Vector2,
	Vector3 = library.Vector3,
	Vector2int16 = library.Vector2int16,
	Vector3int16 = library.Vector3int16,
	CFrame = library.CFrame,
	Ray = library.Ray,
	Region3 = library.Region3,
	RaycastParams = library.RaycastParams,
	Random = library.Random,
	OverlapParams = library.OverlapParams,
	Color3 = library.Color3,
	BrickColor = library.BrickColor,
	UDim = library.UDim,
	UDim2 = library.UDim2,
	Rect = library.Rect,
	NumberRange = library.NumberRange,
	NumberSequence = library.NumberSequence,
	NumberSequenceKeypoint = library.NumberSequenceKeypoint,
	ColorSequence = library.ColorSequence,
	ColorSequenceKeypoint = library.ColorSequenceKeypoint,
	Enum = library.Enum,
	Font = library.Font,
	TweenInfo = library.TweenInfo,
	Content = library.Content,
	FloatCurveKey = library.FloatCurveKey,
	Path2DControlPoint = library.Path2DControlPoint,
	typeName = library.typeName,
	typeof = library.typeof,
	enumType = library.enumType,
	isAttributeType = library.isAttributeType,
	readCFrame = library.readCFrame,
}
