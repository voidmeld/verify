--!strict

local Verify = require "./core"

type Context = Verify.Context
type Expectation = Verify.Expectation
type Harness = Verify.Harness

export type Spy = Verify.Spy

export type Own = (cleanup: () -> ()) -> ()
export type Body = (own: Own, context: Context) -> ()

export type Bdd = {
	describe: (name: string, register: () -> ()) -> (),
	it: (name: string, body: Body) -> (),
	itSkip: (name: string, reason: string, body: Body?) -> (),
	beforeEach: (body: Body) -> (),
	afterEach: (body: Body) -> (),
	expect: (value: unknown) -> Expectation,
	spy: (implementation: ((...any) -> ...any)?) -> Spy,
	skip: (reason: string) -> never,
}

local function create(harness: Harness): Bdd
	local bdd = {} :: Bdd
	local activeContext: Context? = nil

	local function adapt(body: Body): (Context) -> ()
		return function(context: Context)
			local previous = activeContext
			activeContext = context
			local ok, message = pcall(function(): unknown
				body(function(cleanup: () -> ())
					context:defer(cleanup)
				end, context)
				return nil
			end)
			activeContext = previous
			if not ok then
				error(message, 0)
			end
		end
	end

	function bdd.describe(name: string, register: () -> ())
		harness:suite(name, register)
	end

	function bdd.it(name: string, body: Body)
		harness:case(name, adapt(body))
	end

	function bdd.itSkip(name: string, reason: string, body: Body?)
		local adapted = if body ~= nil then adapt(body) else nil
		harness:skip(name, reason, adapted)
	end

	function bdd.beforeEach(body: Body)
		harness:beforeEach(adapt(body))
	end

	function bdd.afterEach(body: Body)
		harness:afterEach(adapt(body))
	end

	function bdd.expect(value: unknown): Expectation
		return Verify.expect(value)
	end

	bdd.spy = Verify.spy

	function bdd.skip(reason: string): never
		local context = activeContext
		if context == nil then
			error("BDD skip must be called while a case or hook is running", 2)
		end
		return context:skip(reason)
	end

	return bdd
end

return {
	create = create,
}
