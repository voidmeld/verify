--!strict

local Environment = require "./environment-types"
local D = require "./datatypes"

type Instance = Environment.Instance
type Vector = D.Vector3Value
type Frame = D.CFrameValue
type Volume = { frame: Frame, half: Vector, kind: string }
type Edit = { volume: Volume, material: D.EnumMember, source: D.EnumMember? }
type Span = { first: number, last: number, entry: Vector, exit: Vector, edit: Edit }
export type Hit = { t: number, normal: Vector, material: D.EnumMember }
export type Controller = {
	authored: (Instance) -> boolean,
	ray: (Instance, Vector, Vector, boolean) -> Hit?,
}
local V = D.Vector3

local function finite(n: number)
	assert(n == n and math.abs(n) < math.huge, "terrain values must be finite")
end

local function vector(v: Vector)
	assert(D.typeName(v) == "Vector3", "terrain requires Vector3")
	finite(v.X)
	finite(v.Y)
	finite(v.Z)
end

local function volume(cf: Frame, size: Vector, kind: string): Volume
	assert(D.typeName(cf) == "CFrame", "terrain requires CFrame")
	for _, n in { cf:GetComponents() } do
		finite(n)
	end
	vector(size)
	assert(size.X > 0 and size.Y > 0 and size.Z > 0, "terrain dimensions must be positive")
	local x, y, z = cf.RightVector, cf.UpVector, cf.ZVector
	assert(
		math.abs(x.Magnitude - 1) < 0.0001
			and math.abs(y.Magnitude - 1) < 0.0001
			and math.abs(z.Magnitude - 1) < 0.0001
			and math.abs(x:Dot(y)) < 0.0001
			and (x:Cross(y) - z).Magnitude < 0.0001,
		"terrain requires an orthonormal CFrame"
	)
	return { frame = cf, half = size / 2, kind = kind }
end

local function material(value: D.EnumMember)
	assert(D.typeName(value) == "EnumItem" and D.enumType(value) == "Material", "terrain requires Enum.Material")
end

local function regionBox(region: D.Region3Value, resolution: number): Volume
	assert(D.typeName(region) == "Region3", "terrain requires Region3")
	assert(resolution == 4, "terrain voxel resolution must be four")
	local box = volume(region.CFrame, region.Size, "box")
	local corners: { Vector } = { region.CFrame.Position - box.half, region.CFrame.Position + box.half }
	for _, corner in corners do
		assert(corner.X % 4 == 0 and corner.Y % 4 == 0 and corner.Z % 4 == 0, "terrain region must align to four")
	end
	assert(region.Size.X * region.Size.Y * region.Size.Z / 64 <= 4194304, "terrain region exceeds voxel limit")
	return box
end

local function interval(edit: Edit, origin: Vector, direction: Vector): Span?
	local shape = edit.volume
	local p, d = shape.frame:PointToObjectSpace(origin), shape.frame:VectorToObjectSpace(direction)
	local near, far, entry, exit = -math.huge, math.huge, V.zero, V.zero
	local function clip(first: number, last: number, a: Vector, b: Vector)
		if first > last then
			first, last, a, b = last, first, b, a
		end
		if first > near then
			near, entry = first, a
		end
		if last < far then
			far, exit = last, b
		end
	end
	local function slab(o: number, delta: number, half: number, axis: Vector): boolean
		if delta == 0 then
			return if edit.source ~= nil then o >= -half and o < half else math.abs(o) <= half
		end
		clip((-half - o) / delta, (half - o) / delta, -axis, axis)
		return near <= far
	end
	if shape.kind == "box" then
		if
			not slab(p.X, d.X, shape.half.X, V.xAxis)
			or not slab(p.Y, d.Y, shape.half.Y, V.yAxis)
			or not slab(p.Z, d.Z, shape.half.Z, V.zAxis)
		then
			return nil
		end
	else
		local sphere = shape.kind == "ball"
		local a = d.X * d.X + d.Z * d.Z + (if sphere then d.Y * d.Y else 0)
		local b = p.X * d.X + p.Z * d.Z + (if sphere then p.Y * d.Y else 0)
		local c = p.X * p.X + p.Z * p.Z + (if sphere then p.Y * p.Y else 0) - shape.half.X ^ 2
		if a == 0 then
			if c > 0 then
				return nil
			end
		else
			local discriminant = b * b - a * c
			if discriminant < 0 then
				return nil
			end
			local first, last = (-b - math.sqrt(discriminant)) / a, (-b + math.sqrt(discriminant)) / a
			local function normal(t: number): Vector
				local point = p + d * t
				return (if sphere then point else V.new(point.X, 0, point.Z)).Unit
			end
			clip(first, last, normal(first), normal(last))
		end
		if not sphere and not slab(p.Y, d.Y, shape.half.Y, V.yAxis) then
			return nil
		end
	end
	if near > far or far < 0 or near > 1 then
		return nil
	end
	return {
		first = near,
		last = far,
		entry = shape.frame:VectorToWorldSpace(entry),
		exit = shape.frame:VectorToWorldSpace(exit),
		edit = edit,
	}
end

local function attach(environment: Environment.Environment): Controller
	local edits: { [Instance]: { Edit } } = setmetatable({}, { __mode = "ks" })
	local air, water = D.Enum.Material.Air, D.Enum.Material.Water
	local function append(terrain: Instance, edit: Edit)
		local rows = edits[terrain] or {}
		edits[terrain] = rows
		table.insert(rows, edit)
	end
	local function fill(terrain: Instance, shape: Volume, value: D.EnumMember)
		material(value)
		append(terrain, { volume = shape, material = value })
	end
	environment.fake("Terrain.FillBlock", function(terrain: Instance, cf: Frame, size: Vector, value: D.EnumMember)
		fill(terrain, volume(cf, size, "box"), value)
	end)
	environment.fake(
		"Terrain.FillBall",
		function(terrain: Instance, center: Vector, radius: number, value: D.EnumMember)
			vector(center)
			finite(radius)
			fill(terrain, volume(D.CFrame.new(center), V.one * (radius * 2), "ball"), value)
		end
	)
	environment.fake(
		"Terrain.FillCylinder",
		function(terrain: Instance, cf: Frame, height: number, radius: number, value: D.EnumMember)
			finite(height)
			finite(radius)
			fill(terrain, volume(cf, V.new(radius * 2, height, radius * 2), "cylinder"), value)
		end
	)
	environment.fake("Terrain.Clear", function(terrain: Instance)
		edits[terrain] = {}
	end)
	environment.fake(
		"Terrain.ReplaceMaterial",
		function(
			terrain: Instance,
			region: D.Region3Value,
			resolution: number,
			source: D.EnumMember,
			target: D.EnumMember
		)
			local box = regionBox(region, resolution)
			material(source)
			material(target)
			append(terrain, { volume = box, material = target, source = source })
		end
	)
	environment.fake(
		"Terrain.WriteVoxels",
		function(
			terrain: Instance,
			region: D.Region3Value,
			resolution: number,
			materials: { { { D.EnumMember } } },
			occupancy: { { { number } } }
		)
			local box = regionBox(region, resolution)
			local size, minimum = region.Size / 4, region.CFrame.Position - box.half
			assert(#materials == size.X and #occupancy == size.X, "voxel width mismatch")
			local pending: { Edit } = { { volume = box, material = air } }
			for x = 1, size.X do
				assert(#materials[x] == size.Y and #occupancy[x] == size.Y, "voxel height mismatch")
				for y = 1, size.Y do
					assert(#materials[x][y] == size.Z and #occupancy[x][y] == size.Z, "voxel depth mismatch")
					for z = 1, size.Z do
						local value, amount = materials[x][y][z], occupancy[x][y][z]
						material(value)
						finite(amount)
						assert(amount >= 0 and amount <= 1, "voxel occupancy must be between zero and one")
						if amount > 0 and value ~= air then
							local dimensions = V.new(4, 4 * amount, 4)
							local center = minimum + V.new((x - 1) * 4, (y - 1) * 4, (z - 1) * 4) + dimensions / 2
							table.insert(
								pending,
								{ volume = volume(D.CFrame.new(center), dimensions, "box"), material = value }
							)
						end
					end
				end
			end
			for _, edit in pending do
				append(terrain, edit)
			end
		end
	)
	local function ray(terrain: Instance, origin: Vector, direction: Vector, ignoreWater: boolean): Hit?
		local spans: { Span } = {}
		local boundaries: { { t: number, normal: Vector } } = {}
		for _, edit in edits[terrain] or {} do
			local span = interval(edit, origin, direction)
			if span then
				table.insert(spans, span)
				table.insert(boundaries, { t = span.first, normal = span.entry })
				table.insert(boundaries, { t = span.last, normal = -span.exit })
			end
		end
		table.sort(boundaries, function(a: { t: number, normal: Vector }, b: { t: number, normal: Vector })
			return a.t < b.t
		end)
		local function at(t: number): D.EnumMember
			local current = air
			for _, span in spans do
				if t >= span.first and t < span.last then
					local edit = span.edit
					if edit.source == nil or (current ~= air and current == edit.source) then
						current = edit.material
					end
				end
			end
			return if ignoreWater and current == water then air else current
		end
		for index, boundary in boundaries do
			local t = boundary.t
			if t < 0 or t > 1 then
				continue
			end
			local previous = if index > 1 then boundaries[index - 1].t else t - 1
			local following = if index < #boundaries then boundaries[index + 1].t else t + 1
			if previous == t then
				continue
			end
			local nextIndex = index + 1
			while following == t and nextIndex <= #boundaries do
				nextIndex += 1
				following = if nextIndex <= #boundaries then boundaries[nextIndex].t else t + 1
			end
			local before, after = at((previous + t) / 2), at((t + following) / 2)
			if after ~= air and (before == air or before == water and after ~= water) then
				return { t = t, normal = boundary.normal, material = after }
			end
		end
		return nil
	end
	return {
		authored = function(terrain)
			return edits[terrain] ~= nil
		end,
		ray = ray,
	}
end

return { attach = attach }
