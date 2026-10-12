--!strict

local Core = require "../src/core"
local Datatypes = require "../src/roblox/datatypes"

return function(suite: Core.Harness)
	suite:suite("CFrame matrix constructor", function()
		suite:case("uses translation and basis columns without transposing", function(check)
			local vector = Datatypes.Vector3.new
			local position = vector(3, -2, 7)
			local right = vector(0, 0, -1)
			local up = vector(0, 1, 0)
			local back = vector(1, 0, 0)
			local frame = Datatypes.CFrame.fromMatrix(position, right, up, back)
			check:expect(frame.Position == position):toEqual(true)
			check:expect(frame.RightVector == right):toEqual(true)
			check:expect(frame.UpVector == up):toEqual(true)
			check:expect(frame.LookVector == -back):toEqual(true)
			local world = frame * vector(2, 3, 4)
			check:expect(world == vector(7, 1, 5)):toEqual(true)
			check:expect(frame:Inverse() * world == vector(2, 3, 4)):toEqual(true)
		end)
		suite:case("normalizes only the omitted third column", function(check)
			local vector = Datatypes.Vector3.new
			local frame = Datatypes.CFrame.fromMatrix(vector(0, 0, 0), vector(2, 0, 0), vector(0, 3, 0))
			check:expect(frame.RightVector == vector(2, 0, 0)):toEqual(true)
			check:expect(frame.UpVector == vector(0, 3, 0)):toEqual(true)
			check:expect(frame.ZVector == vector(0, 0, 1)):toEqual(true)
			local explicit =
				Datatypes.CFrame.fromMatrix(vector(0, 0, 0), vector(2, 0, 0), vector(0, 3, 0), vector(0, 0, 6))
			check:expect(explicit.ZVector == vector(0, 0, 6)):toEqual(true)
		end)
	end)
end
