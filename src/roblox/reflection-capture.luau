--!strict

type Fields = { [string]: unknown }
type Encode = (value: unknown, kind: string) -> unknown
type EnumItem = { Name: string, Value: number }
type EnumFamily = { GetEnumItems: (EnumFamily) -> { EnumItem } }
type Enums = { GetEnums: (Enums) -> { EnumFamily }, [string]: EnumFamily }
type BrickColor = { Number: number, Name: string, Color: { R: number, G: number, B: number } }
type Font = { Family: string, Weight: EnumItem, Style: EnumItem }
type Node = { [string]: unknown, Destroy: (Node) -> () }
type Reflection = {
	GetClass: (Reflection, string, Fields?) -> ReflectedMember?,
	GetClasses: (Reflection, Fields?) -> { ReflectedMember },
	GetPropertiesOfClass: (Reflection, string, Fields?) -> { ReflectedMember }?,
	GetEventsOfClass: (Reflection, string, Fields?) -> { ReflectedMember }?,
	GetMethodsOfClass: (Reflection, string, Fields?) -> { ReflectedMember }?,
}
type Game = { GetService: (Game, string) -> Reflection, FindService: (Game, string) -> Node? }
type Globals = {
	game: Game,
	Instance: { new: (className: string) -> Node },
	Enum: Enums,
	BrickColor: { new: (number) -> BrickColor, palette: (number) -> BrickColor },
	Font: { fromEnum: (EnumItem) -> Font },
	typeof: (unknown) -> string,
	version: (() -> string)?,
	security: unknown,
	classSecurity: unknown,
}
type Request = {
	part: string,
	names: { string }?,
	services: boolean?,
}
type ReflectedType = { EngineType: string, ScriptType: string?, EnumType: string? }
type ReflectedMember = {
	Name: string,
	Owner: string?,
	Superclass: string?,
	Type: ReflectedType?,
	Permits: { [string]: unknown }?,
	Display: { DeprecationMessage: string? }?,
}

local RENAMES: { [string]: string } = {
	bool = "Bool",
	float = "Float32",
	double = "Float64",
	int = "Int32",
	int64 = "Int64",
	string = "String",
	ProtectedString = "String",
	CoordinateFrame = "CFrame",
	OptionalCoordinateFrame = "OptionalCFrame",
	Rect2D = "Rect",
	Vector2Int16 = "Vector2int16",
	Vector3Int16 = "Vector3int16",
	Region3Int16 = "Region3int16",
	RefType = "Ref",
}

local SKIPPED: { [string]: boolean } = { Parent = true, ClassName = true }

local function reflection(globals: Globals): Reflection
	return globals.game:GetService "ReflectionService"
end

local function filter(globals: Globals): Fields
	return { Security = globals.security }
end

local function sorted(values: { string }): { string }
	table.sort(values)
	return values
end

local function deprecated(member: ReflectedMember): boolean
	local display = member.Display
	return display ~= nil and display.DeprecationMessage ~= nil
end

local function datatype(kind: ReflectedType): string
	if kind.EngineType == "Enum" then
		return "Enum." .. tostring(kind.EnumType)
	end
	return RENAMES[kind.EngineType] or kind.EngineType
end

local function property(member: ReflectedMember): Fields
	local permits: { [string]: unknown } = member.Permits or {}
	local readable, writable = permits.Read ~= nil, permits.Write ~= nil
	local tags: { string } = {}
	if readable and not writable then
		table.insert(tags, "ReadOnly")
	elseif not readable and not writable then
		table.insert(tags, "NotScriptable")
	end
	if deprecated(member) then
		table.insert(tags, "Deprecated")
	end
	return {
		datatype = datatype(assert(member.Type)),
		scriptability = if readable and writable
			then "ReadWrite"
			elseif readable then "Read"
			elseif writable then "Write"
			else "None",
		tags = sorted(tags),
	}
end

local function sample(globals: Globals, encode: Encode, object: Node, members: { ReflectedMember }): Fields
	local defaults: Fields = {}
	for _, member in members do
		local permits: { [string]: unknown } = member.Permits or {}
		if permits.Read ~= nil and not SKIPPED[member.Name] then
			local read, value = pcall(function(): unknown
				return object[member.Name]
			end)
			if read and value ~= nil then
				local encoded = encode(value, globals.typeof(value))
				if encoded ~= nil then
					defaults[member.Name] = encoded
				end
			end
		end
	end
	return defaults
end

local function class(globals: Globals, encode: Encode, name: string, services: boolean): Fields
	local service = reflection(globals)
	local current = service:GetClass(name)
	local plugin = if current == nil then service:GetClass(name, filter(globals)) else nil
	local permitted = current or plugin
	local scope = if current == nil and plugin ~= nil then filter(globals) else nil
	local reflected = permitted or service:GetClass(name, { Security = globals.classSecurity })
	assert(reflected ~= nil, "Studio reflection has no class " .. name)
	local function membersOf(
		method: string,
		fetch: (Reflection, string, Fields?) -> { ReflectedMember }?
	): { ReflectedMember }
		local members = fetch(service, name, scope)
		assert(members ~= nil or permitted == nil, "Studio reflection returned no " .. method .. " for " .. name)
		return members or {}
	end
	local members = membersOf("GetPropertiesOfClass", service.GetPropertiesOfClass)
	local permits: { [string]: unknown } = if permitted then permitted.Permits or {} else {}
	local tags: { string } = {}
	if permits.New == nil then
		table.insert(tags, "NotCreatable")
	end
	if permits.GetService ~= nil then
		table.insert(tags, "Service")
	end
	if deprecated(reflected) then
		table.insert(tags, "Deprecated")
	end
	local properties: Fields = {}
	for _, member in members do
		if member.Owner == name and member.Type ~= nil then
			properties[member.Name] = property(member)
		end
	end
	local events: { string } = {}
	for _, member in membersOf("GetEventsOfClass", service.GetEventsOfClass) do
		if member.Owner == name and member.Permits ~= nil and member.Permits.Listen ~= nil then
			table.insert(events, member.Name)
		end
	end
	local methods: { string } = {}
	for _, member in membersOf("GetMethodsOfClass", service.GetMethodsOfClass) do
		if member.Owner == name and member.Permits ~= nil and member.Permits.Call ~= nil then
			table.insert(methods, member.Name)
		end
	end
	local defaults: Fields = {}
	if permits.New ~= nil then
		local created, object = pcall(globals.Instance.new, name)
		if created and object ~= nil then
			defaults = sample(globals, encode, object, members)
			pcall(object.Destroy, object)
		end
	elseif services and permits.GetService ~= nil then
		local found, object = pcall(globals.game.FindService, globals.game, name)
		if found and object ~= nil then
			defaults = sample(globals, encode, object, members)
		end
	end
	return {
		superclass = reflected.Superclass,
		tags = sorted(tags),
		properties = properties,
		defaults = defaults,
		events = sorted(events),
		methods = sorted(methods),
	}
end

local function index(globals: Globals): Fields
	local classes: { { name: string, superclass: string? } } = {}
	for _, reflected in reflection(globals):GetClasses { Security = globals.classSecurity } do
		local entry = { name = reflected.Name, superclass = reflected.Superclass }
		table.insert(classes, entry)
	end
	table.sort(
		classes,
		function(left: { name: string, superclass: string? }, right: { name: string, superclass: string? }): boolean
			return left.name < right.name
		end
	)
	local enums: { string } = {}
	for _, family in globals.Enum:GetEnums() do
		table.insert(enums, tostring(family))
	end
	return {
		classes = classes,
		enums = sorted(enums),
		engineVersion = if globals.version ~= nil then globals.version() else nil,
	}
end

local function enums(globals: Globals, names: { string }): Fields
	local out: Fields = {}
	for _, name in names do
		local family = globals.Enum[name]
		local items: { { name: string, value: number } } = {}
		for _, item in family:GetEnumItems() do
			table.insert(items, { name = item.Name, value = item.Value })
		end
		out[name] = items
	end
	return out
end

local function engine(globals: Globals): Fields
	local colors: { Fields } = {}
	for number = 0, 1032 do
		local color = globals.BrickColor.new(number)
		if color.Number == number then
			local value = color.Color
			local entry: Fields = {}
			entry.number, entry.name, entry.color = number, color.Name, { value.R, value.G, value.B }
			table.insert(colors, entry)
		end
	end
	local palette: { number } = {}
	for slot = 0, 127 do
		table.insert(palette, globals.BrickColor.palette(slot).Number)
	end
	local fonts: Fields = {}
	local family = globals.Enum.Font
	for _, item in family:GetEnumItems() do
		local converted, font = pcall(globals.Font.fromEnum, item)
		if converted then
			local fields = font
			fonts[item.Name] = {
				family = fields.Family,
				weight = fields.Weight.Name,
				style = fields.Style.Name,
			}
		end
	end
	return { brickColors = { colors = colors, palette = palette }, fonts = fonts }
end

local function capture(globals: Globals, encode: Encode, request: Request): Fields
	local names: { string } = request.names or {}
	if request.part == "index" then
		return index(globals)
	elseif request.part == "classes" then
		local out: Fields = {}
		for _, name in names do
			out[name] = class(globals, encode, name, request.services == true)
		end
		return out
	elseif request.part == "enums" then
		return enums(globals, names)
	elseif request.part == "engine" then
		return engine(globals)
	end
	error("unknown reflection capture part: " .. tostring(request.part))
end

return { capture = capture }
