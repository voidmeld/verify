--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local fs = require "@std/fs"
local system = require "@std/system"
local task = require "@std/task"

local Files = require "../src/lute/files"
local Install = require "../src/lute/studio-install"

describe("Roblox Studio installation", function()
	it("picks the newest version directory that holds Studio on Windows", function(own)
		local root = Files.claimDirectory ".lute/tmp/verify-studio-install"
		own(function()
			fs.removeDirectory(root, { recursive = true })
		end)
		local versions = root .. "/Roblox/Versions"
		Files.ensureDirectory(versions .. "/version-player")
		fs.writeStringToFile(versions .. "/version-player/RobloxPlayerBeta.exe", "")
		Files.ensureDirectory(versions .. "/version-old")
		fs.writeStringToFile(versions .. "/version-old/RobloxStudioBeta.exe", "")
		task.wait(1.1)
		Files.ensureDirectory(versions .. "/version-new")
		fs.writeStringToFile(versions .. "/version-new/RobloxStudioBeta.exe", "")
		local found = Install.windows(root)
		expect(found):toEqual {
			studio = versions .. "/version-new/RobloxStudioBeta.exe",
			mcp = versions .. "/version-new/StudioMCP.exe",
		}
	end)

	it("names what is missing instead of guessing a Studio", function(own)
		local root = Files.claimDirectory ".lute/tmp/verify-studio-install"
		own(function()
			fs.removeDirectory(root, { recursive = true })
		end)
		local empty, why = Install.windows(root)
		expect(empty):toBeNil()
		expect(why):toContain "no RobloxStudioBeta.exe exists under"
		local unset, reason = Install.windows(nil)
		expect(unset):toBeNil()
		expect(reason):toContain "LOCALAPPDATA is not set"
	end)

	it("keeps the macOS application paths off Windows", function()
		local found = Install.locate()
		if not system.win32 then
			expect(found):toEqual(Install.MACOS)
		elseif found ~= nil then
			expect(string.sub(found.studio, -21)):toEqual "/RobloxStudioBeta.exe"
			expect(string.sub(found.mcp, -14)):toEqual "/StudioMCP.exe"
		end
	end)
end)

return nil
