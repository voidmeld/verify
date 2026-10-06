--!strict

export type Call = {
	args: { unknown },
	returnValue: unknown,
}

export type Spy<A... = ...unknown> = {
	fn: (A...) -> ...unknown,

	calls: { Call },
	callCount: () -> number,
	called: () -> boolean,
	lastArgs: () -> { unknown }?,
	lastReturn: () -> unknown,
	reset: () -> (),
	returnValue: (value: unknown) -> (),
	implementation: (f: (A...) -> ...unknown) -> (),
}

local function arguments(...: unknown): { unknown }
	return { ... }
end

local function on<A...>(implementation: ((A...) -> ...unknown)?): Spy<A...>
	local calls: { Call } = {}
	local recordArguments = (arguments :: unknown) :: (A...) -> { unknown }

	local current: (A...) -> ...unknown = implementation or function(...: A...) end

	local spy: Spy<A...> = {
		calls = calls,
		callCount = function()
			return #calls
		end,
		called = function()
			return #calls > 0
		end,
		lastArgs = function()
			return if #calls > 0 then calls[#calls].args else nil
		end,
		lastReturn = function()
			return if #calls > 0 then calls[#calls].returnValue else nil
		end,
		reset = function()
			table.clear(calls)
		end,
		returnValue = function(value: unknown)
			current = function(...: A...)
				return value
			end
		end,
		implementation = function(f: (A...) -> ...unknown)
			current = f
		end,
		fn = function(...: A...): ...unknown
			local returned = { current(...) }
			table.insert(calls, { args = recordArguments(...), returnValue = returned[1] })
			return table.unpack(returned)
		end,
	}

	return spy
end

return {
	on = on,
}
