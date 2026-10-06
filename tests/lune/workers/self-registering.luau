--!strict

local Lune = require "../../../src/lune"
local Common = require "./common"
local Verify = require "../../../src/core"

Lune.selfRegisteringWorker {
	load = function(locator: string, harness)
		local registration = Common.operations.load(locator) :: (Verify.Harness) -> ()
		registration(harness)
	end,
}
