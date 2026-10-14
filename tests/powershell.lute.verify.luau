--!strict

local process = require "@std/process"
local system = require "@std/system"

local Base64 = require "../src/codec/base64"
local Powershell = require "../src/lute/powershell"
local Verify = require "../src/core"

return function(suite: Verify.Harness)
	suite:suite("encoded PowerShell commands", function()
		suite:case("passes the script as UTF-16 so quotes and non-ASCII text arrive intact", function(check)
			local argv = Powershell.command "'a'"
			check:expect(argv[1]):toEqual "powershell"
			check:expect(argv[#argv - 1]):toEqual "-EncodedCommand"
			check:expect(argv[#argv]):toEqual(Base64.encode "'\0a\0'\0")
			if system.win32 then
				local ran = process.run(Powershell.command "Write-Output ('say \"{0}\" {1}' -f 'hi', 'é'.Length)")
				check:expect(ran.exitcode):toEqual(0)
				check:expect(ran.stdout):toEqual 'say "hi" 1\r\n'
			end
		end)
	end)
end
