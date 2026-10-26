--!strict

export type Probe = { name: string, source: string, tolerance: number? }

local PREAMBLE = [[
local function n(...)
	local values = table.pack(...)
	local out = {}
	for index = 1, values.n do
		out[index] = string.format("%.9g", values[index])
	end
	return table.concat(out, " ")
end
local function s(...)
	local values = table.pack(...)
	local out = {}
	for index = 1, values.n do
		out[index] = tostring(values[index])
	end
	return table.concat(out, " | ")
end
]]

local probes: { Probe } = {
	{ name = "vector2 tostring", source = "return s(Vector2.new(1.5, -2), Vector2.new(1 / 3, 1e20))" },
	{
		name = "vector2 non-finite",
		source = "return s(Vector2.new(math.huge, -math.huge), Vector2.new(0 / 0, 0).X ~= 0)",
	},
	{ name = "vector2 float32", source = "return n(Vector2.new(1 / 3, 0.1).X, Vector2.new(1 / 3, 0.1).Y)" },
	{ name = "vector2 coerce", source = 'return s(Vector2.new(), Vector2.new("3", 4), Vector2.new(1))' },
	{
		name = "vector2 arithmetic",
		source = "local a, b = Vector2.new(1, 3), Vector2.new(2, 0.5) return s(a + b, a - b, a * b, a / b, a * 2, 2 * a, a / 2, 6 / a, Vector2.new(5, 7) // 2, -a)",
	},
	{ name = "vector2 add number", source = "return s(Vector2.new(1, 3) + 1)" },
	{ name = "vector2 sub number", source = "return s(Vector2.new(1, 3) - 1)" },
	{
		name = "vector2 members",
		source = "local v = Vector2.new(3, 4) return s(v.Magnitude, v.Unit, n(Vector2.new(1, 1).Magnitude), v.x, v.y)",
	},
	{ name = "vector2 unit zero", source = "local u = Vector2.zero.Unit return s(u.X ~= u.X, u.Y ~= u.Y)" },
	{
		name = "vector2 methods",
		source = "local v = Vector2.new(-1.5, 3.5) return s(v:Abs(), v:Floor(), v:Ceil(), v:Sign(), Vector2.new(0, -2):Sign(), v:Dot(Vector2.new(2, 1)), v:Cross(Vector2.new(1, 0)))",
	},
	{
		name = "vector2 max min",
		source = "local v = Vector2.new(-1.5, 3) return s(v:Max(Vector2.new(0, 1), Vector2.new(-5, 9)), v:Min(Vector2.new(0, 1)))",
	},
	{
		name = "vector2 lerp",
		source = "return s(Vector2.new(0, 0):Lerp(Vector2.new(1, 3), 1 / 3), Vector2.new(2, 4):Lerp(Vector2.new(-2, 0), 0.25))",
	},
	{
		name = "vector2 angle",
		source = "local x = Vector2.new(1, 0) return n(x:Angle(Vector2.new(0, 1)), x:Angle(Vector2.new(0, -1)), x:Angle(Vector2.new(0, -1), true))",
	},
	{
		name = "vector2 fuzzy",
		source = "local v = Vector2.new(1, 1) return s(v:FuzzyEq(Vector2.new(1.000001, 1)), v:FuzzyEq(Vector2.new(1.001, 1)), v:FuzzyEq(Vector2.new(1.05, 1), 0.1), Vector2.new(1000, 0):FuzzyEq(Vector2.new(1000.005, 0)), Vector2.new(0, 0):FuzzyEq(Vector2.new(0.000005, 0)))",
	},
	{ name = "vector2 fuzzy epsilon", source = "return s(Vector2.new(1, 1):FuzzyEq(Vector2.new(1, 1), 0.2))" },
	{
		name = "vector2 constants",
		source = "return s(Vector2.zero, Vector2.one, Vector2.xAxis, Vector2.yAxis, Vector2.zero == Vector2.new(0, 0))",
	},
	{
		name = "vector2 equality",
		source = "local nan = Vector2.new(0 / 0, 0) return s(Vector2.new(1, 2) == Vector2.new(1, 2), Vector2.new(1, 2) == Vector2.new(1, 3), nan == nan, Vector2.new(1 / 3, 0) == Vector2.new(0.33333334, 0))",
	},
	{ name = "vector2 type", source = "return s(typeof(Vector2.zero), type(Vector2.zero))" },
	{ name = "vector2 write", source = "local v = Vector2.new(1, 2) v.X = 5 return s(v)" },
	{ name = "vector2 missing", source = "return s(Vector2.new(1, 2).Z)" },
	{ name = "vector3 tostring", source = "return s(Vector3.new(1.5, 1e20, -0.1), Vector3.new(1 / 3, 0.1, 100000))" },
	{
		name = "vector3 arithmetic",
		source = "local a, b = Vector3.new(1, 2, 3), Vector3.new(2, 2, 0.5) return s(a + b, a - b, a * b, a / b, a * 2, 2 * a, a / 2, Vector3.new(5, 7, 9) // 2, -a)",
	},
	{ name = "vector3 add number", source = "return s(Vector3.new(1, 2, 3) + 1)" },
	{
		name = "vector3 members",
		source = "local v = Vector3.new(2, 3, 6) return s(v.Magnitude, v.Unit, n(Vector3.new(1, 1, 1).Magnitude), v.x, v.z)",
	},
	{
		name = "vector3 methods",
		source = "local v = Vector3.new(1, 0, 0) return s(v:Cross(Vector3.new(0, 1, 0)), v:Dot(Vector3.new(3, 1, 1)), n(v:Angle(Vector3.new(0, 1, 0))), Vector3.new(-1.5, 2.5, 0):Floor(), Vector3.new(-1.5, 2.5, 0):Sign(), v:Lerp(Vector3.new(0, 2, 4), 0.5), v:Max(Vector3.new(0, 3, -1)), v:FuzzyEq(Vector3.new(1.000001, 0, 0)))",
	},
	{
		name = "vector3 signed angle",
		source = "return n(Vector3.new(1, 0, 0):Angle(Vector3.new(0, 0, 1), Vector3.new(0, 1, 0)), Vector3.new(1, 0, 0):Angle(Vector3.new(0, 0, -1), Vector3.new(0, 1, 0)))",
	},
	{
		name = "vector3 constants",
		source = "return s(Vector3.zero, Vector3.one, Vector3.xAxis, Vector3.yAxis, Vector3.zAxis)",
	},
	{
		name = "vector3 from enums",
		source = "return s(Vector3.FromNormalId(Enum.NormalId.Top), Vector3.FromNormalId(Enum.NormalId.Front), Vector3.FromAxis(Enum.Axis.Z))",
	},
	{ name = "vector3 type", source = "return s(typeof(Vector3.zero))" },
	{
		name = "vector2int16",
		source = "return s(Vector2int16.new(1, 40000), Vector2int16.new(-3.7, 2) + Vector2int16.new(1, 1))",
	},
	{
		name = "vector3int16",
		source = "return s(Vector3int16.new(1, 2, -3.7), Vector3int16.new(1, 2, 3) * Vector3int16.new(2, 2, 2), typeof(Vector3int16.new()))",
	},
	{ name = "cframe tostring", source = "return s(CFrame.new(1, 2, 3), CFrame.new())" },
	{ name = "cframe angles", source = "return s(CFrame.Angles(0, math.pi / 2, 0), CFrame.Angles(0.3, 0.2, 0.1))" },
	{
		name = "cframe orientation",
		source = "return s(CFrame.fromOrientation(0.3, 0.2, 0.1), CFrame.fromEulerAnglesYXZ(0.3, 0.2, 0.1))",
	},
	{
		name = "cframe look at",
		source = "local frame = CFrame.lookAt(Vector3.new(0, 0, 0), Vector3.new(1, 0, 0)) return s(frame, frame.LookVector, frame.RightVector, frame.UpVector)",
	},
	{
		name = "cframe look at up",
		source = "return s(CFrame.lookAt(Vector3.new(1, 2, 3), Vector3.new(1, 5, 3)))",
	},
	{ name = "cframe quaternion", source = "return s(CFrame.new(1, 2, 3, 0, 0.7071068, 0, 0.7071068))" },
	{
		name = "cframe compose",
		source = "local a = CFrame.new(1, 2, 3) * CFrame.Angles(0, math.pi / 2, 0) local b = CFrame.new(4, 0, 0) return s(a * b, a * Vector3.new(1, 0, 0), a + Vector3.new(1, 1, 1), a - Vector3.new(1, 1, 1))",
	},
	{
		name = "cframe spaces",
		source = "local a = CFrame.new(1, 2, 3) * CFrame.Angles(0, math.pi / 2, 0) return s(a:Inverse(), a:PointToObjectSpace(Vector3.new(1, 2, 4)), a:PointToWorldSpace(Vector3.new(0, 0, 1)), a:VectorToWorldSpace(Vector3.new(0, 0, 1)), a:VectorToObjectSpace(Vector3.new(0, 0, 1)), a:ToObjectSpace(CFrame.new(1, 2, 4)), a:ToWorldSpace(CFrame.new(0, 0, 1)))",
	},
	{
		name = "cframe members",
		source = "local a = CFrame.new(1, 2, 3) * CFrame.Angles(0, math.pi / 2, 0) return s(a.Position, a.X, a.Z, a.LookVector, a.Rotation, a.XVector, a.ZVector)",
	},
	{
		name = "cframe euler",
		source = "local frame = CFrame.Angles(0.3, 0.2, 0.1) local x, y, z = frame:ToEulerAnglesXYZ() local a, b, c = CFrame.fromOrientation(0.3, 0.2, 0.1):ToOrientation() return n(x, y, z, a, b, c)",
	},
	{
		name = "cframe axis angle",
		source = "local axis, angle = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), 0.5):ToAxisAngle() return s(CFrame.fromAxisAngle(Vector3.new(0, 1, 0), 0.5), axis, n(angle))",
		tolerance = 1e-6,
	},
	{
		name = "cframe lerp",
		source = "return s(CFrame.new(0, 0, 0):Lerp(CFrame.new(2, 4, 6) * CFrame.Angles(0, math.pi / 2, 0), 0.5))",
		tolerance = 1e-6,
	},
	{
		name = "cframe equality",
		source = "return s(CFrame.new(1, 2, 3) == CFrame.new(1, 2, 3), CFrame.new(1, 2, 3) == CFrame.new(1, 2, 4), CFrame.identity == CFrame.new(), select('#', CFrame.new():GetComponents()))",
	},
	{ name = "cframe type", source = "return s(typeof(CFrame.new()))" },
	{
		name = "color3 tostring",
		source = "return s(Color3.new(1, 0.5, 0), Color3.fromRGB(255, 128, 0), Color3.new(1 / 3, 0.1, 2), Color3.new())",
	},
	{
		name = "color3 float32",
		source = "local c = Color3.fromRGB(128, 64, 1) return n(c.R, c.G, c.B, Color3.fromRGB(127.6, 300, -5).R, Color3.fromRGB(127.6, 300, -5).G)",
	},
	{
		name = "color3 hsv",
		source = "local out = {} for _, h in { 0, 0.1, 0.25, 0.5, 0.75, 0.99, 1, 1.05, 1.25, 2, -0.25 } do local c = Color3.fromHSV(h, 0.7, 0.9) table.insert(out, n(c.R, c.G, c.B)) end return table.concat(out, ' / ')",
	},
	{
		name = "color3 hsv sweep",
		source = "local out = {} for index = 0, 12 do local c = Color3.fromHSV(index / 12 + 0.01, 0.8, 0.6) table.insert(out, n(c.R, c.G, c.B)) end return table.concat(out, ' / ')",
	},
	{
		name = "color3 to hsv",
		source = "local out = {} for _, c in { Color3.fromRGB(10, 200, 50), Color3.new(0.5, 0.5, 0.5), Color3.new(0, 0, 0), Color3.new(1, 0, 0.5), Color3.new(0.2, 0.3, 0.9), Color3.new(2, 0.5, -1), Color3.new(0.9, 0.9, 0.1) } do table.insert(out, n(c:ToHSV())) end return table.concat(out, ' / ')",
	},
	{ name = "color3 static to hsv", source = "return n(Color3.toHSV(Color3.new(0.2, 0.3, 0.9)))" },
	{
		name = "color3 hex",
		source = "return s(Color3.fromRGB(10, 200, 50):ToHex(), Color3.new(0.5, 0.25, 0.999):ToHex(), Color3.new(2, -1, 0.5):ToHex(), Color3.new(0.5 / 255, 1.5 / 255, 2.5 / 255):ToHex(), n(Color3.fromHex('#0AC832').G), n(Color3.fromHex('FA0').G))",
	},
	{ name = "color3 hex invalid", source = "return s(Color3.fromHex('zz'))" },
	{
		name = "color3 lerp",
		source = "return n(Color3.new(0, 0, 0):Lerp(Color3.new(1, 1, 1), 1 / 3).R, Color3.new(1, 0, 0):Lerp(Color3.new(0, 0, 1), 0.25).B)",
	},
	{
		name = "color3 equality",
		source = "return s(Color3.fromRGB(128, 64, 1) == Color3.new(128 / 255, 64 / 255, 1 / 255), Color3.new(1, 0, 0) == Color3.new(1, 0, 0.1))",
	},
	{ name = "color3 lowercase", source = "return s(Color3.new(0.25, 0.5, 1).r, Color3.new(0.25, 0.5, 1).b)" },
	{ name = "color3 missing", source = "return s(Color3.new(1, 2, 3).A)" },
	{ name = "color3 type", source = "return s(typeof(Color3.new()))" },
	{
		name = "udim offsets",
		source = "return s(UDim.new(0.5, 10.7), UDim.new(0.5, -10.7), UDim.new(0.5, 10.5), UDim.new(0.5, 3e9), UDim.new(1 / 3, 0))",
	},
	{
		name = "udim arithmetic",
		source = "return s(UDim.new(0.5, 10) + UDim.new(0.25, 3), UDim.new(1, 2) - UDim.new(0.5, 1), -UDim.new(1, 2), UDim.new(1, 2) == UDim.new(1, 2))",
	},
	{ name = "udim multiply", source = "return s(UDim.new(0.5, 10) * 2)" },
	{ name = "udim lerp", source = "return s(UDim.new(0, 0):Lerp(UDim.new(1, 5), 0.5))" },
	{
		name = "udim2 constructors",
		source = "return s(UDim2.new(0.5, 10, 1, -4), UDim2.new(), UDim2.new(1), UDim2.new(UDim.new(1, 2), UDim.new(3, 4)), UDim2.fromScale(0.3, 0.7), UDim2.fromOffset(10.7, -3.2))",
	},
	{
		name = "udim2 arithmetic",
		source = "local a, b = UDim2.new(0.5, 10, 1, -4), UDim2.new(0.25, 3, 0, 1) return s(a + b, a - b, -a, a == UDim2.new(0.5, 10, 1, -4))",
	},
	{ name = "udim2 add udim", source = "return s(UDim2.new() + UDim.new(1, 2))" },
	{ name = "udim2 multiply", source = "return s(UDim2.new(0.5, 10, 1, -4) * 2)" },
	{
		name = "udim2 lerp",
		source = "local zero = UDim2.new() return s(zero:Lerp(UDim2.new(1, 11, 1, 21), 0.5), zero:Lerp(UDim2.new(1, -11, 1, -21), 0.5), zero:Lerp(UDim2.new(1, 10, 1, 20), 0.33))",
	},
	{
		name = "udim2 members",
		source = "local u = UDim2.new(0.25, 3, 0.75, 4) return s(u.X, u.Width, u.Y.Offset, u.Height.Scale, typeof(u.X), typeof(u))",
	},
	{
		name = "rect",
		source = "local r = Rect.new(1, 2, 3, 5) return s(r, r.Width, r.Height, r.Min, r.Max, Rect.new(4, 5, 1, 2), Rect.new(Vector2.new(4, 5), Vector2.new(1, 2)), Rect.new(), Rect.new(1 / 3, 0.1, 2.5, 1e10), typeof(r))",
	},
	{
		name = "rect equality",
		source = "return s(Rect.new(1, 2, 3, 4) == Rect.new(Vector2.new(1, 2), Vector2.new(3, 4)))",
	},
	{
		name = "number range",
		source = "return s(NumberRange.new(1, 2), NumberRange.new(3), NumberRange.new(1 / 3, 2.5), NumberRange.new(1, 2) == NumberRange.new(1, 2), NumberRange.new(1, 2).Min, typeof(NumberRange.new(1)))",
	},
	{ name = "number range invalid", source = "return s(NumberRange.new(3, 1))" },
	{
		name = "number sequence",
		source = "local k = NumberSequenceKeypoint.new(0.5, 2, 0.1) return s(NumberSequence.new(0.5), NumberSequence.new(0, 1), NumberSequence.new(1 / 3), k, k.Envelope, NumberSequenceKeypoint.new(0, 1).Envelope, typeof(k))",
	},
	{
		name = "number sequence keypoints",
		source = "local q = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 0) }) return s(#q.Keypoints, q.Keypoints[2], typeof(q.Keypoints[2]), q.Keypoints == q.Keypoints, q == NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 0) }))",
	},
	{
		name = "number sequence end",
		source = "return s(NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 1) }))",
	},
	{
		name = "number sequence start",
		source = "return s(NumberSequence.new({ NumberSequenceKeypoint.new(0.2, 0), NumberSequenceKeypoint.new(1, 1) }))",
	},
	{
		name = "number sequence order",
		source = "return s(NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 1), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 0) }))",
	},
	{
		name = "color sequence",
		source = "local k = ColorSequenceKeypoint.new(0.25, Color3.new(0, 1, 0)) return s(ColorSequence.new(Color3.new(1, 0, 0)), ColorSequence.new(Color3.new(1, 0, 0), Color3.new(0, 0, 1)), k, k.Time, k.Value, #ColorSequence.new(Color3.new()).Keypoints, typeof(k))",
	},
	{
		name = "color sequence count",
		source = "return s(ColorSequence.new({ ColorSequenceKeypoint.new(0.2, Color3.new()) }))",
	},
	{
		name = "brick color palette",
		source = "local names = {} for index = 0, 127 do names[BrickColor.palette(index).Name] = true end local count = 0 for _ in names do count += 1 end return s(BrickColor.palette(0), BrickColor.palette(1), BrickColor.palette(127), count)",
	},
	{ name = "brick color palette bound", source = "return s(BrickColor.palette(128))" },
	{
		name = "brick color new",
		source = "return s(BrickColor.new('Bright red'), BrickColor.new(21).Number, BrickColor.new('Lilac').Number, BrickColor.new('No such color'), BrickColor.new(0), BrickColor.new(), BrickColor.new('Bright red') == BrickColor.new(21), typeof(BrickColor.new(1)))",
	},
	{
		name = "brick color closest",
		source = "local out = {} for _, c in { Color3.new(1, 0, 0), Color3.new(0.5, 0.2, 0.9), Color3.new(0.1, 0.8, 0.3), Color3.new(0.95, 0.95, 0.2), Color3.new(0.3, 0.3, 0.3), Color3.new(0.6, 0.4, 0.2) } do table.insert(out, BrickColor.new(c).Number) end table.insert(out, BrickColor.new(0.5, 0.2, 0.9).Number) return table.concat(out, ' ')",
	},
	{
		name = "brick color members",
		source = "local b = BrickColor.new('Bright red') return s(b.Color, n(b.r, b.g, b.b), b.Name, b.Number)",
	},
	{
		name = "brick color presets",
		source = "return s(BrickColor.White(), BrickColor.Gray(), BrickColor.DarkGray(), BrickColor.Black(), BrickColor.Red(), BrickColor.Yellow(), BrickColor.Green(), BrickColor.Blue())",
	},
	{
		name = "enum strings",
		source = "return s(Enum.FontWeight.Bold, Enum.FontWeight, Enum, typeof(Enum.FontWeight.Bold), typeof(Enum.FontWeight), typeof(Enum), type(Enum.FontWeight.Bold))",
	},
	{
		name = "enum members",
		source = "local item = Enum.FontWeight.Bold return s(item.Name, item.Value, item.EnumType, item.EnumType == Enum.FontWeight, item:IsA('FontWeight'), item:IsA('Enum.FontWeight'), item:IsA('FontStyle'))",
	},
	{
		name = "enum lookups",
		source = "return s(Enum.FontWeight:FromName('Heavy'), Enum.FontWeight:FromName('Nope'), Enum.FontWeight:FromValue(300), Enum.FontWeight:FromValue(-5), Enum.TextXAlignment:FromValue(2))",
	},
	{
		name = "enum items",
		source = "local out = {} for _, item in Enum.FontWeight:GetEnumItems() do table.insert(out, item.Name .. '=' .. item.Value) end return table.concat(out, ' ')",
	},
	{
		name = "enum items copy",
		source = "local a = Enum.FontStyle:GetEnumItems() table.insert(a, 1) return s(#Enum.FontStyle:GetEnumItems(), a[1] == Enum.FontStyle:GetEnumItems()[1])",
	},
	{ name = "enum missing item", source = "return s(Enum.FontWeight.Nope)" },
	{ name = "enum missing family", source = "return s(Enum.Nope)" },
	{ name = "enum item missing member", source = "return s(Enum.FontWeight.Bold.Size)" },
	{ name = "enum item write", source = "Enum.FontWeight.Bold.Name = 'x' return 'written'" },
	{ name = "enum compare", source = "return s(Enum.FontWeight.Bold < Enum.FontWeight.Heavy)" },
	{
		name = "enum equality",
		source = "return s(Enum.FontWeight.Bold == Enum.FontWeight.Bold, Enum.FontWeight.Bold == Enum.FontWeight.Heavy, Enum.FontStyle.Normal == Enum.FontWeight.Regular)",
	},
	{
		name = "font constructors",
		source = "return s(Font.new('rbxasset://fonts/families/GothamSSm.json'), Font.new('x', Enum.FontWeight.Bold, Enum.FontStyle.Italic), Font.fromName('GothamSSm', Enum.FontWeight.Medium), Font.fromName('Arial'), Font.fromId(12187365364), Font.fromId('12'))",
	},
	{
		name = "font from enum",
		source = "return s(Font.fromEnum(Enum.Font.SourceSansBold), Font.fromEnum(Enum.Font.Legacy), Font.fromEnum(Enum.Font.GothamBold), Font.fromEnum(Enum.Font.Code))",
	},
	{ name = "font from enum unknown", source = "return s(Font.fromEnum(Enum.Font.Unknown))" },
	{
		name = "font members",
		source = "local f = Font.fromEnum(Enum.Font.GothamBold) return s(f.Family, f.Weight, f.Style, f.Bold, Font.new('x', Enum.FontWeight.SemiBold).Bold, Font.new('x', Enum.FontWeight.Medium).Bold, typeof(f))",
	},
	{
		name = "font mutation",
		source = "local f = Font.fromEnum(Enum.Font.Gotham) f.Bold = true local a = tostring(f) f.Weight = Enum.FontWeight.Heavy local b = tostring(f) f.Bold = false f.Family = 'y' f.Style = Enum.FontStyle.Italic return s(a, b, f)",
	},
	{ name = "font invalid weight", source = "return s(Font.new('x', Enum.FontStyle.Italic))" },
	{ name = "font missing member", source = "return s(Font.new('x').Size)" },
	{
		name = "font equality",
		source = "return s(Font.fromEnum(Enum.Font.Gotham) == Font.new('rbxasset://fonts/families/GothamSSm.json'), Font.new('x') == Font.new('x', Enum.FontWeight.Bold))",
	},
	{
		name = "tween info",
		source = "local t = TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 2, true, 0.1) return s(TweenInfo.new(), t, n(t.Time, t.DelayTime), t.RepeatCount, t.Reverses, t.EasingStyle, TweenInfo.new(1) == TweenInfo.new(1), typeof(t))",
	},
	{ name = "tween info write", source = "local t = TweenInfo.new() t.Time = 3 return s(t)" },
	{
		name = "content",
		source = "local c = Content.fromUri('rbxassetid://1') return s(c, Content.none, c.SourceType, c.Uri, c.Object, Content.none.Uri, Content.fromAssetId(5), Content.fromUri('a') == Content.fromUri('a'), Content.none == Content.none, typeof(c))",
	},
	{
		name = "path2d control point",
		source = "local p = Path2DControlPoint.new(UDim2.new(0.5, 1, 0.5, 2), UDim2.new(0, 1, 0, 0), UDim2.new(0, -1, 0, 0)) return s(Path2DControlPoint.new(UDim2.new(0.5, 1, 0.5, 2)), p, p.Position, p.LeftTangent, typeof(p))",
	},
	{
		name = "float curve key",
		source = "local k = FloatCurveKey.new(0.5, 2, Enum.KeyInterpolationMode.Cubic) local before = tostring(k) k.LeftTangent = 1.5 return s(before, k, k.Interpolation, k.RightTangent, typeof(k), FloatCurveKey.new(0, 1, Enum.KeyInterpolationMode.Linear) == FloatCurveKey.new(0, 1, Enum.KeyInterpolationMode.Linear))",
	},
}

local spatial: { Probe } = {
	{
		name = "query instance filters",
		source = "local p = RaycastParams.new() local a, b = Instance.new('Part'), Instance.new('Folder') p.FilterDescendantsInstances = {a, {b}} local count = #p.FilterDescendantsInstances local copy = p.FilterDescendantsInstances table.clear(copy) p:AddToFilter(a) local added = #p.FilterDescendantsInstances local ok = pcall(function() p.FilterDescendantsInstances = {42} end) local invalid = #p.FilterDescendantsInstances a:Destroy() b:Destroy() return s(count, added, ok, invalid)",
	},
	{
		name = "part pivot and position",
		source = "local p = Instance.new('Part') p.PivotOffset = CFrame.new(0, 1, 0) p:PivotTo(CFrame.new(8, 4, -2) * CFrame.Angles(0, math.pi/2, 0)) local pivot, position = p:GetPivot(), p.Position p.Position = Vector3.new(2, 3, 4) local frame = p.CFrame p:Destroy() return s(pivot.Position, position, frame.Position, frame.LookVector)",
		tolerance = 1e-6,
	},
	{
		name = "model bounds and movement",
		source = "local m, a, b = Instance.new('Model'), Instance.new('Part'), Instance.new('Part') a.Size, a.CFrame = Vector3.new(2, 4, 6), CFrame.new(4, 2, 0) * CFrame.Angles(0, math.pi/2, 0) b.Size, b.CFrame = Vector3.new(2, 2, 2), CFrame.new(10, 1, 0) a.Parent, b.Parent = m, m local initial = m:GetPivot() local box, size = m:GetBoundingBox() m:PivotTo(CFrame.new(30, 8, -4)) local target = m:GetPivot() b.Position = Vector3.new(100, 0, 0) local retained = m:GetPivot() m:Destroy() return s(initial.Position, box.Position, size, target.Position, retained.Position)",
		tolerance = 1e-6,
	},
	{
		name = "empty model pivot",
		source = "local m = Instance.new('Model') local p = m:GetPivot() m:Destroy() return s(p.Position)",
	},
	{
		name = "ray projection",
		source = "local r = Ray.new(Vector3.new(1, 2, 3), Vector3.new(2, 0, 0)) return s(r, r.Unit, r:ClosestPoint(Vector3.new(4, 6, 3)), r:ClosestPoint(Vector3.new(-4, 6, 3)), r:Distance(Vector3.new(4, 6, 3)), typeof(r), r == Ray.new(r.Origin, r.Direction))",
	},
	{
		name = "ray zero",
		source = "local r = Ray.new() return s(r.Origin, r.Direction, r:ClosestPoint(Vector3.new(2, 3, 4)), r:Distance(Vector3.new(2, 3, 4)))",
		tolerance = 1e-7,
	},
	{
		name = "spatial immutability",
		source = "local r = Ray.new() local region = Region3.new(Vector3.zero, Vector3.one) return s(pcall(function() r.Origin = Vector3.one end), pcall(function() region.Size = Vector3.zero end))",
	},
	{
		name = "region bounds and grid",
		source = "local r = Region3.new(Vector3.new(-3, 1, 5), Vector3.new(2, 6, 10)) local g = r:ExpandToGrid(4) return s(r.CFrame.Position, r.Size, g.CFrame.Position, g.Size, typeof(r), r == Region3.new(Vector3.new(-3, 1, 5), Vector3.new(2, 6, 10)))",
	},
	{
		name = "region reversed bounds",
		source = "local r = Region3.new(Vector3.one, Vector3.zero) return s(r.CFrame.Position, r.Size)",
	},
	{
		name = "query defaults",
		source = "local r, o = RaycastParams.new(), OverlapParams.new() return s(typeof(r), r.FilterType, #r.FilterDescendantsInstances, r.IncludeInstances, r.ExcludeInstances, r.CollisionGroup, r.IgnoreWater, r.RespectCanCollide, r.BruteForceAllSlow, typeof(o), o.MaxParts, o.Tolerance)",
	},
	{
		name = "query mutation",
		source = "local r, o = RaycastParams.new(), OverlapParams.new() r.IgnoreWater = true r.FilterType = Enum.RaycastFilterType.Include r.CollisionGroup = 'Characters' o.MaxParts = 3.9 o.Tolerance = 4 return s(r.IgnoreWater, r.FilterType, r.CollisionGroup, o.MaxParts, o.Tolerance)",
		tolerance = 1e-7,
	},
}
for _, probe in spatial do
	table.insert(probes, probe)
end

local list: { Probe } = {}
for _, probe in probes do
	table.insert(list, { name = probe.name, source = PREAMBLE .. probe.source, tolerance = probe.tolerance })
end

return list
