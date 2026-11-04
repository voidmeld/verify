--!strict

local json = require "@std/json"

local FIELDS = { "advances", "adjustments", "starts", "ends" }

local function pack(faces: { [string]: json.Object }): string
	local vectors: json.Array = {}
	local indices: { [string]: number } = {}
	local function intern(values: json.Array): number
		local source = json.serialize(values)
		local index = indices[source]
		if index == nil then
			index = #vectors + 1
			indices[source] = index
			table.insert(vectors, values)
		end
		return index
	end
	local names: { string } = {}
	for name in faces do
		table.insert(names, name)
	end
	table.sort(names)
	local packed: json.Object = {}
	for _, name in names do
		local face = table.clone(faces[name])
		local rows = assert(json.asArray(face.sizes))
		local sizes: json.Array = {}
		for _, entry in rows do
			table.insert(sizes, table.clone(assert(json.asObject(entry))))
		end
		local columns: json.Object = {}
		for _, field in FIELDS do
			local first = json.asArray(assert(json.asObject(rows[1]))[field])
			local complete = first ~= nil
			for _, entry in rows do
				local row = json.asArray(assert(json.asObject(entry))[field])
				complete = complete and row ~= nil and first ~= nil and #row == #first
			end
			if first == nil or not complete then
				continue
			end
			local references: json.Array = {}
			for index in first do
				local values: json.Array = {}
				for _, entry in rows do
					local row = assert(json.asArray(assert(json.asObject(entry))[field]))
					table.insert(values, row[index])
				end
				table.insert(references, intern(values))
			end
			columns[field] = intern(references)
			for _, entry in sizes do
				assert(json.asObject(entry))[field] = nil
			end
		end
		face.tokens = intern(assert(json.asArray(face.tokens)))
		face.pairs = intern(assert(json.asArray(face.pairs)))
		face.sizes, face.columns = sizes, columns
		packed[name] = face
	end
	return json.serialize(json.object { faces = json.object(packed), vectors = vectors })
end

local function open(source: string): { [string]: () -> json.Object }
	local archive = assert(json.asObject(json.deserialize(source)))
	local vectors = assert(json.asArray(archive.vectors))
	local function vector(value: json.Value): json.Array
		assert(type(value) == "number" and value % 1 == 0 and value >= 1 and value <= #vectors)
		return assert(json.asArray(vectors[value]))
	end
	local faces: { [string]: () -> json.Object } = {}
	for name, entry in assert(json.asObject(archive.faces)) do
		if type(name) ~= "string" then
			continue
		end
		local face = assert(json.asObject(entry))
		faces[name] = function(): json.Object
			local result = table.clone(face)
			result.tokens, result.pairs = vector(face.tokens), vector(face.pairs)
			local sizes: json.Array = {}
			for _, row in assert(json.asArray(face.sizes)) do
				table.insert(sizes, table.clone(assert(json.asObject(row))))
			end
			local columns = assert(json.asObject(face.columns))
			for _, field in FIELDS do
				local references = columns[field]
				if references == nil then
					continue
				end
				local rows: { json.Array } = {}
				for _, entry in sizes do
					local row: json.Array = {}
					assert(json.asObject(entry))[field] = row
					table.insert(rows, row)
				end
				for _, reference in vector(references) do
					local column = vector(reference)
					assert(#column == #sizes)
					for size, value in column do
						table.insert(rows[size], value)
					end
				end
			end
			result.sizes, result.columns = sizes, nil
			return result
		end
	end
	return faces
end

return { pack = pack, open = open }
