--!strict

export type Row = { checkpoint: string, viewport: string, kind: string? }
export type Ordered = { driven: { any }, undriven: { any } }

local function order(
	checkpoints: { string },
	viewports: { string },
	rows: { any },
	collectAll: boolean?
): (Ordered?, string?)
	if type(checkpoints) ~= "table" or type(viewports) ~= "table" or type(rows) ~= "table" then
		return nil, "checkpoint_plan_invalid"
	end
	local names: { [string]: boolean } = {}
	local views: { [string]: boolean } = {}
	for _, name in checkpoints do
		if type(name) ~= "string" or name == "" or names[name] then
			return nil, "checkpoint_plan_invalid"
		end
		names[name] = true
	end
	for _, view in viewports do
		if type(view) ~= "string" or view == "" or views[view] then
			return nil, "checkpoint_plan_invalid"
		end
		views[view] = true
	end
	local selected: { [string]: any } = {}
	local undriven = {}
	for _, row in rows do
		if type(row) ~= "table" or type(row.checkpoint) ~= "string" or type(row.viewport) ~= "string" then
			return nil, "checkpoint_row_invalid"
		end
		if row.kind == "checkpoint" then
			local key = row.viewport .. "\0" .. row.checkpoint
			if selected[key] ~= nil then
				return nil, "checkpoint_row_duplicate: " .. row.checkpoint .. " on " .. row.viewport
			end
			selected[key] = row
		else
			table.insert(undriven, row)
		end
	end
	if collectAll == true then
		return { driven = {}, undriven = {} }, nil
	end
	local driven = {}
	for _, checkpoint in checkpoints do
		for _, viewport in viewports do
			local row = selected[viewport .. "\0" .. checkpoint]
			if row == nil then
				return nil, "checkpoint_row_missing: " .. checkpoint .. " on " .. viewport
			end
			table.insert(driven, row)
		end
	end
	return { driven = driven, undriven = undriven }, nil
end

return { order = order }
