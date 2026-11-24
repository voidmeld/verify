--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Datatypes = require "../src/roblox/datatypes"

describe("CFrame matrix constructor", function()
	it("uses translation and basis columns without transposing", function()
		local vector = Datatypes.Vector3.new
		local position = vector(3, -2, 7)
		local right = vector(0, 0, -1)
		local up = vector(0, 1, 0)
		local back = vector(1, 0, 0)
		local frame = Datatypes.CFrame.fromMatrix(position, right, up, back)
		expect(frame.Position == position):toEqual(true)
		expect(frame.RightVector == right):toEqual(true)
		expect(frame.UpVector == up):toEqual(true)
		expect(frame.LookVector == -back):toEqual(true)
		local world = frame * vector(2, 3, 4)
		expect(world == vector(7, 1, 5)):toEqual(true)
		expect(frame:Inverse() * world == vector(2, 3, 4)):toEqual(true)
	end)
	it("normalizes only the omitted third column", function()
		local vector = Datatypes.Vector3.new
		local frame = Datatypes.CFrame.fromMatrix(vector(0, 0, 0), vector(2, 0, 0), vector(0, 3, 0))
		expect(frame.RightVector == vector(2, 0, 0)):toEqual(true)
		expect(frame.UpVector == vector(0, 3, 0)):toEqual(true)
		expect(frame.ZVector == vector(0, 0, 1)):toEqual(true)
		local explicit = Datatypes.CFrame.fromMatrix(vector(0, 0, 0), vector(2, 0, 0), vector(0, 3, 0), vector(0, 0, 6))
		expect(explicit.ZVector == vector(0, 0, 6)):toEqual(true)
	end)
end)

return nil
