--!strict

local Environment = require "./environment-types"
local Names = require "./datatypes/names"
local Enum = require "./datatypes/enum"

export type Options = {
	assetVersion: ((number) -> Environment.Instance?)?,
	terrainMaterialColor: ((Enum.EnumItem) -> unknown)?,
}

local function attach(environment: Environment.Environment, options: Options?)
	local settings: Options = options or {}
	local owned = setmetatable({} :: { [Environment.Object]: boolean }, { __mode = "k" })
	environment.onCreate(function(object)
		owned[object] = true
	end)
	environment.fake("InsertService.LoadAssetVersion", function(service: Environment.Instance, version: number)
		assert(
			type(version) == "number" and version > 0 and version < math.huge and version % 1 == 0,
			"asset version must be a positive finite integer"
		)
		local provider = settings.assetVersion
		assert(provider ~= nil, "unsupported_content: InsertService.LoadAssetVersion requires an assetVersion provider")
		local source = provider(version)
		assert(source ~= nil, "asset version unavailable: " .. tostring(version))
		assert(
			owned[source] == true and environment.isAlive(source) and source:IsA "Model",
			"assetVersion provider must return a live Model in this environment"
		)
		local model = assert(source:Clone(), "assetVersion Model must be Archivable")
		local ok, failure = pcall(function()
			model.Parent = service
		end)
		if not ok then
			model:Destroy()
			error(failure, 0)
		end
		return model
	end)
	local colors = setmetatable({} :: { [Environment.Instance]: { [string]: unknown } }, { __mode = "k" })
	local function material(value: Enum.EnumItem): string
		assert(Names.kind(value) == "EnumItem" and value:IsA "Material", "terrain material must be Enum.Material")
		assert(value.Name ~= "Air" and value.Name ~= "Water", "terrain material does not support custom colors")
		return value.Name
	end
	local function color(value: unknown): unknown
		assert(Names.kind(value) == "Color3", "terrain material color must be Color3")
		return value
	end
	environment.fake(
		"Terrain.SetMaterialColor",
		function(terrain: Environment.Instance, value: Enum.EnumItem, tint: unknown)
			local key = material(value)
			local checked = color(tint)
			local palette = colors[terrain] or {}
			palette[key] = checked
			colors[terrain] = palette
		end
	)
	environment.fake("Terrain.GetMaterialColor", function(terrain: Environment.Instance, value: Enum.EnumItem): unknown
		local key = material(value)
		local palette = colors[terrain]
		if palette and palette[key] ~= nil then
			return palette[key]
		end
		local provider = settings.terrainMaterialColor
		assert(
			provider ~= nil,
			"unsupported_content: Terrain.GetMaterialColor requires a captured color or SetMaterialColor"
		)
		return color(provider(value))
	end)
	environment.onClone(function(source, copy)
		if colors[source] then
			colors[copy] = table.clone(colors[source])
		end
	end)
end

return { attach = attach }
