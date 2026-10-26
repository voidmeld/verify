--!strict

local D = require "./datatypes"

type Vector = D.Vector3Value
type Frame = D.CFrameValue
export type Shape = { frame: Frame, half: Vector, radius: number? }
local V = D.Vector3
local basis = { V.xAxis, V.yAxis, V.zAxis }

local function components(v: Vector): { number }
	return { v.X, v.Y, v.Z }
end

local function axes(s: Shape): { Vector }
	return { s.frame.RightVector, s.frame.UpVector, s.frame.ZVector }
end

local function closest(s: Shape, point: Vector): Vector
	local p, h = s.frame:PointToObjectSpace(point), s.half
	return s.frame * V.new(math.clamp(p.X, -h.X, h.X), math.clamp(p.Y, -h.Y, h.Y), math.clamp(p.Z, -h.Z, h.Z))
end

local function separating(a: Shape, b: Shape): { Vector }
	local aa, bb = axes(a), axes(b)
	local result = { aa[1], aa[2], aa[3], bb[1], bb[2], bb[3] }
	for _, x in aa do
		for _, y in bb do
			local cross = x:Cross(y)
			if cross.Magnitude > 1e-7 then
				table.insert(result, cross.Unit)
			end
		end
	end
	return result
end

local function projection(s: Shape, axis: Vector): number
	local h, aa = components(s.half), axes(s)
	return h[1] * math.abs(aa[1]:Dot(axis)) + h[2] * math.abs(aa[2]:Dot(axis)) + h[3] * math.abs(aa[3]:Dot(axis))
end

local function overlaps(a: Shape, b: Shape): boolean
	if a.radius ~= nil and b.radius ~= nil then
		return (a.frame.Position - b.frame.Position).Magnitude <= a.radius + b.radius
	elseif a.radius ~= nil then
		return (a.frame.Position - closest(b, a.frame.Position)).Magnitude <= a.radius
	elseif b.radius ~= nil then
		return overlaps(b, a)
	end
	local delta = a.frame.Position - b.frame.Position
	for _, axis in separating(a, b) do
		if math.abs(delta:Dot(axis)) > projection(a, axis) + projection(b, axis) then
			return false
		end
	end
	return true
end

local function sphereTime(origin: Vector, direction: Vector, radius: number): number?
	local aa, bb, cc = direction:Dot(direction), origin:Dot(direction), origin:Dot(origin) - radius * radius
	local discriminant = bb * bb - aa * cc
	if aa == 0 or discriminant < 0 then
		return nil
	end
	local t = (-bb - math.sqrt(discriminant)) / aa
	return if t >= 0 and t <= 1 then t else nil
end

local function sphereBox(sphere: Shape, box: Shape, direction: Vector): (number?, Vector?, Vector?)
	local origin = box.frame:PointToObjectSpace(sphere.frame.Position)
	local delta = box.frame:VectorToObjectSpace(direction)
	local o, d, h = components(origin), components(delta), components(box.half)
	local times = { 0, 1 }
	for i = 1, 3 do
		if d[i] ~= 0 then
			for sign = -1, 1, 2 do
				local t = (sign * h[i] - o[i]) / d[i]
				if t > 0 and t < 1 then
					table.insert(times, t)
				end
			end
		end
	end
	table.sort(times)
	local radius = assert(sphere.radius)
	for i = 1, #times - 1 do
		local first, last = times[i], times[i + 1]
		local middle = (first + last) / 2
		local aa, bb, cc = 0, 0, -radius * radius
		for j = 1, 3 do
			local position = o[j] + d[j] * middle
			if math.abs(position) > h[j] then
				local offset = o[j] - (if position > 0 then h[j] else -h[j])
				aa += d[j] * d[j]
				bb += offset * d[j]
				cc += offset * offset
			end
		end
		local discriminant = bb * bb - aa * cc
		if aa > 0 and discriminant >= 0 then
			local t = (-bb - math.sqrt(discriminant)) / aa
			if t >= first - 1e-7 and t <= last + 1e-7 and t >= 0 and t <= 1 then
				local center = sphere.frame.Position + direction * t
				local point = closest(box, center)
				local offset = center - point
				if offset.Magnitude > 0 then
					return t, offset.Unit, point
				end
			end
		end
	end
	return nil, nil, nil
end

local function vertices(s: Shape): { Vector }
	local result = {}
	for x = -1, 1, 2 do
		for y = -1, 1, 2 do
			for z = -1, 1, 2 do
				table.insert(result, s.frame * V.new(x * s.half.X, y * s.half.Y, z * s.half.Z))
			end
		end
	end
	return result
end

local function contact(a: Shape, b: Shape): Vector
	local points: { Vector } = {}
	for _, pair in { { a, b }, { b, a } } do
		local source, target = pair[1], pair[2]
		local corners = vertices(source)
		for i, p in corners do
			if (p - closest(target, p)).Magnitude < 0.0001 then
				table.insert(points, p)
			end
			for j = i + 1, #corners do
				local q = corners[j]
				local difference = bit32.bxor(i - 1, j - 1)
				if difference ~= 1 and difference ~= 2 and difference ~= 4 then
					continue
				end
				local o = components(target.frame:PointToObjectSpace(p))
				local d = components(target.frame:VectorToObjectSpace(q - p))
				local h = components(target.half)
				local near, far = 0, 1
				for k = 1, 3 do
					if math.abs(d[k]) < 1e-8 then
						if math.abs(o[k]) > h[k] + 0.0001 then
							near, far = 1, 0
						end
					else
						local t1, t2 = (-h[k] - o[k]) / d[k], (h[k] - o[k]) / d[k]
						near, far = math.max(near, math.min(t1, t2)), math.min(far, math.max(t1, t2))
					end
				end
				if near <= far + 1e-7 then
					table.insert(points, p + (q - p) * near)
				end
			end
		end
	end
	assert(#points > 0, "unsupported: unable to resolve box contact at this numeric precision")
	local sum = V.zero
	for _, p in points do
		sum += p
	end
	return sum / #points
end

local function cast(a: Shape, direction: Vector, b: Shape): (number?, Vector?, Vector?)
	if overlaps(a, b) then
		return nil, nil, nil
	end
	if a.radius ~= nil and b.radius ~= nil then
		local t = sphereTime(a.frame.Position - b.frame.Position, direction, a.radius + b.radius)
		if t ~= nil then
			local normal = (a.frame.Position + direction * t - b.frame.Position).Unit
			return t, normal, b.frame.Position + normal * b.radius
		end
		return nil, nil, nil
	elseif a.radius ~= nil then
		return sphereBox(a, b, direction)
	elseif b.radius ~= nil then
		local t, normal = sphereBox(b, a, -direction)
		if t ~= nil then
			local n = -assert(normal)
			return t, n, b.frame.Position + n * b.radius
		end
		return nil, nil, nil
	end
	local delta = a.frame.Position - b.frame.Position
	local near, far, normal = -math.huge, math.huge, V.zero
	for _, axis in separating(a, b) do
		local radius = projection(a, axis) + projection(b, axis)
		local offset, speed = delta:Dot(axis), direction:Dot(axis)
		if math.abs(speed) < 1e-9 then
			if math.abs(offset) > radius then
				return nil, nil, nil
			end
		else
			local first, last = (-radius - offset) / speed, (radius - offset) / speed
			local face = -axis
			if first > last then
				first, last, face = last, first, axis
			end
			if first > near then
				near, normal = first, face
			end
			far = math.min(far, last)
			if near > far then
				return nil, nil, nil
			end
		end
	end
	if near < 0 or near > 1 then
		return nil, nil, nil
	end
	local moved: Shape = { frame = a.frame + direction * near, half = a.half }
	return near, normal, contact(moved, b)
end

local function ray(a: Shape, direction: Vector, b: Shape): (number?, Vector?, Vector?)
	if b.radius ~= nil then
		return cast(a, direction, b)
	end
	local o = components(b.frame:PointToObjectSpace(a.frame.Position))
	local d, h = components(b.frame:VectorToObjectSpace(direction)), components(b.half)
	local near, far, normal = -math.huge, math.huge, V.zero
	for i = 1, 3 do
		if d[i] == 0 then
			if math.abs(o[i]) > h[i] then
				return nil, nil, nil
			end
		else
			local first, last = (-h[i] - o[i]) / d[i], (h[i] - o[i]) / d[i]
			local face = -basis[i]
			if first > last then
				first, last, face = last, first, basis[i]
			end
			if first > near then
				near, normal = first, face
			end
			far = math.min(far, last)
			if near > far then
				return nil, nil, nil
			end
		end
	end
	if near < 0 or near > 1 then
		return nil, nil, nil
	end
	return near, b.frame:VectorToWorldSpace(normal), a.frame.Position + direction * near
end

return { overlaps = overlaps, cast = cast, ray = ray }
