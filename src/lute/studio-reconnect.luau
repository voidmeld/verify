--!strict

export type Exchange = {
	status: "answered" | "unsent" | "unanswered",
	result: unknown?,
	detail: string?,
	lost: boolean?,
}

export type Connection = {
	callRaw: (name: string, argumentsJson: string, deadline: number, replaySafe: boolean?) -> Exchange,
	close: () -> (),
	alive: () -> boolean,
}

export type Deps = {
	open: (deadline: number) -> Connection,
	now: () -> number,
	wait: (seconds: number) -> (),
}

local function wrap(initial: Connection?, deps: Deps): Connection
	local active: Connection? = initial
	local closed = false
	local function drop()
		local previous = active
		active = nil
		if previous ~= nil then
			pcall(previous.close)
		end
	end
	return {
		alive = function(): boolean
			return not closed and active ~= nil and (active :: Connection).alive()
		end,
		close = function()
			closed = true
			drop()
		end,
		callRaw = function(name, argumentsJson, deadline, replaySafe): Exchange
			local last: Exchange = {
				status = "unsent",
				detail = if closed
					then "Studio MCP connection is closed"
					else "Studio MCP deadline expired before " .. name,
			}
			local uncertain = false
			if closed then
				return last
			end
			for attempt = 1, 3 do
				if closed or deps.now() >= deadline then
					break
				end
				if active == nil then
					local opened, value: unknown = pcall(deps.open, deadline)
					if opened then
						local fresh = value :: Connection
						if closed then
							pcall(fresh.close)
							break
						end
						active = fresh
					else
						last = { status = last.status, detail = tostring(value), lost = true }
					end
				end
				local current = active
				if current ~= nil then
					last = current.callRaw(name, argumentsJson, deadline)
					uncertain = uncertain or last.status == "unanswered"
					if last.lost ~= true then
						if uncertain and last.status == "unsent" then
							return { status = "unanswered", detail = last.detail, lost = last.lost }
						end
						return last
					end
					drop()
					if last.status ~= "unsent" and not replaySafe then
						return last
					end
				end
				if attempt < 3 then
					local remaining = deadline - deps.now()
					if remaining > 0 then
						deps.wait(math.min(0.25 * attempt, remaining))
					end
				end
			end
			if uncertain and last.status == "unsent" then
				last = { status = "unanswered", detail = last.detail, lost = last.lost }
			end
			return last
		end,
	}
end

return { wrap = wrap }
