--!strict

local Core = require "../src/core"
local Lute = require "../src/lute"

return function(suite: Core.Harness)
	suite:case("attenuation curves copy inputs, outputs and cloned emitters", function(check)
		local engine = Lute.fixture.bridge().placeEngine()
		local emitter = engine.newInstance "AudioEmitter"
		local set = emitter.SetDistanceAttenuation :: (typeof(emitter), { [number]: number }?) -> ()
		local get = emitter.GetDistanceAttenuation :: (typeof(emitter)) -> { [number]: number }
		check:expect(get(emitter)):toEqual {}
		local curve = { [0] = 1, [10] = 0.5, [20] = 0 }
		set(emitter, curve)
		curve[10] = 0.1
		get(emitter)[10] = 0.2
		local copy = assert(emitter:Clone())
		local getCopy = copy.GetDistanceAttenuation :: (typeof(copy)) -> { [number]: number }
		check:expect(getCopy(copy)[10]):toBe(0.5)
		set(emitter, nil)
		check:expect(get(emitter)):toEqual {}
		check:expect(getCopy(copy)[10]):toBe(0.5)
	end)
	suite:case("attenuation clamps numeric bounds and retains the curve on invalid keys", function(check)
		local engine = Lute.fixture.bridge().placeEngine()
		local emitter = engine.newInstance "AudioEmitter"
		local set = emitter.SetDistanceAttenuation :: (typeof(emitter), { [unknown]: unknown }) -> ()
		local get = emitter.GetDistanceAttenuation :: (typeof(emitter)) -> { [number]: number }
		set(emitter, { [-1] = 2, [10] = -1 })
		check:expect(get(emitter)):toEqual { [0] = 1, [10] = 0 }
		check:expect((pcall(set, emitter, { bad = 1 }))):toBe(false)
		check:expect(get(emitter)):toEqual { [0] = 1, [10] = 0 }
	end)
end
