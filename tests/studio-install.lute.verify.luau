--!strict

local fs = require "@std/fs"
local system = require "@std/system"
local task = require "@std/task"

local Files = require "../src/lute/files"
local Install = require "../src/lute/studio-install"
local Verify = require "../src/core"

return function(suite: Verify.Harness)
	suite:suite("Roblox Studio installation", function()
		suite:case("picks the newest version directory that holds Studio on Windows", function(check)
			local root = Files.claimDirectory ".lute/tmp/verify-studio-install"
			check:defer(function()
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
			check:expect(found):toEqual {
				studio = versions .. "/version-new/RobloxStudioBeta.exe",
				mcp = versions .. "/version-new/StudioMCP.exe",
			}
		end)

		suite:case("names what is missing instead of guessing a Studio", function(check)
			local root = Files.claimDirectory ".lute/tmp/verify-studio-install"
			check:defer(function()
				fs.removeDirectory(root, { recursive = true })
			end)
			local empty, why = Install.windows(root)
			check:expect(empty):toBeNil()
			check:expect(why):toContain "no RobloxStudioBeta.exe exists under"
			local unset, reason = Install.windows(nil)
			check:expect(unset):toBeNil()
			check:expect(reason):toContain "LOCALAPPDATA is not set"
		end)

		suite:case("keeps the macOS application paths off Windows", function(check)
			local found = Install.locate()
			if not system.win32 then
				check:expect(found):toEqual(Install.MACOS)
			elseif found ~= nil then
				check:expect(string.sub(found.studio, -21)):toEqual "/RobloxStudioBeta.exe"
				check:expect(string.sub(found.mcp, -14)):toEqual "/StudioMCP.exe"
			end
		end)
	end)
end
