--!strict

local Lute = require "../src/lute"
local Ambient = require "./self-registering-ambient"

Lute.selfRegisteringPoolWorker {
	load = function(locator: string, harness)
		Ambient.set(harness)
		local resolved, thrown: any = pcall(require, "../" .. string.sub(locator, 1, #locator - 5))
		Ambient.set(nil)
		if not resolved then
			error(thrown, 0)
		end
	end,
}
