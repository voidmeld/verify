--!strict

local process = require "@std/process"
local system = require "@std/system"

local Powershell = require "../src/lute/powershell"
local Verify = require "../src/core"

return function(suite: Verify.Harness)
	suite:suite("encoded PowerShell commands", function()
		suite:case("encodes base64 for every padding length", function(check)
			check:expect(Powershell.encodeBase64 ""):toEqual ""
			check:expect(Powershell.encodeBase64 "M"):toEqual "TQ=="
			check:expect(Powershell.encodeBase64 "Ma"):toEqual "TWE="
			check:expect(Powershell.encodeBase64 "Man"):toEqual "TWFu"
			check:expect(Powershell.encodeBase64 "\0\255\128"):toEqual "AP+A"
		end)

		suite:case("passes the script as UTF-16 so quotes and non-ASCII text arrive intact", function(check)
			local argv = Powershell.command "'a'"
			check:expect(argv[1]):toEqual "powershell"
			check:expect(argv[#argv - 1]):toEqual "-EncodedCommand"
			check:expect(argv[#argv]):toEqual(Powershell.encodeBase64 "'\0a\0'\0")
			if system.win32 then
				local ran = process.run(Powershell.command "Write-Output ('say \"{0}\" {1}' -f 'hi', 'é'.Length)")
				check:expect(ran.exitcode):toEqual(0)
				check:expect(ran.stdout):toEqual 'say "hi" 1\r\n'
			end
		end)
	end)
end
