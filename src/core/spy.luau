--!strict

export type Call = {
	args: { any },
	returnValue: any,
}

export type Spy = {
	fn: (...any) -> ...any,

	calls: { Call },
	callCount: () -> number,
	called: () -> boolean,
	lastArgs: () -> { any }?,
	lastReturn: () -> any,
	reset: () -> (),
	returnValue: (value: any) -> (),
	implementation: (f: (...any) -> ...any) -> (),
}

local function on(implementation: ((...any) -> ...any)?): Spy
	local calls: { Call } = {}

	local current: (...any) -> ...any = implementation or function(...: any)
		local _ = { ... }
	end

	local spy: Spy = {
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
		returnValue = function(value: any)
			current = function(...: any)
				local _ = { ... }
				return value
			end
		end,
		implementation = function(f: (...any) -> ...any)
			current = f
		end,
		fn = nil :: any,
	}

	spy.fn = function(...: any): ...any
		local returned = { current(...) }
		table.insert(calls, { args = { ... }, returnValue = returned[1] })
		return table.unpack(returned)
	end

	return spy
end

return {
	on = on,
}
