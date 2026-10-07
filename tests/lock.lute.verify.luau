--!strict

local fs = require "@std/fs"
local process = require "@std/process"

local Verify = require "../src/core"
local Lute = require "../src/lute"

return function(suite: Verify.Harness)
	suite:suite("named directory lock", function()
		suite:case("serializes holders, releases and takes over a dead holder", function(check)
			local root = ("/tmp/verify-lock-%d-%d"):format(process.pid(), os.time())
			local acquire, release = Lute.directoryLock(root)
			local first = acquire "desktop"
			check:expect(first ~= nil):toEqual(true)
			assert(first ~= nil)
			local second, why = acquire "desktop"
			check:expect(second):toEqual(nil)
			check:expect(why):toEqual("held_by_" .. tostring(process.pid()))
			release(first)
			local third = acquire "desktop"
			check:expect(third ~= nil):toEqual(true)
			fs.writeStringToFile(tostring(third) .. "/owner", "999999")
			check:expect((acquire "desktop")):toEqual(nil)
			local taken = acquire "desktop"
			check:expect(taken ~= nil):toEqual(true)
			assert(taken ~= nil)
			release(taken)
			process.run { "rm", "-rf", root }
		end)
	end)
end
