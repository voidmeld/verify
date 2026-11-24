--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local process = require "@std/process"
local system = require "@std/system"

local Base64 = require "../src/codec/base64"
local Powershell = require "../src/lute/powershell"

describe("encoded PowerShell commands", function()
	it("passes the script as UTF-16 so quotes and non-ASCII text arrive intact", function()
		local argv = Powershell.command "'a'"
		expect(argv[1]):toEqual "powershell"
		expect(argv[#argv - 1]):toEqual "-EncodedCommand"
		expect(argv[#argv]):toEqual(Base64.encode "'\0a\0'\0")
		if system.win32 then
			local ran = process.run(Powershell.command "Write-Output ('say \"{0}\" {1}' -f 'hi', 'é'.Length)")
			expect(ran.exitcode):toEqual(0)
			expect(ran.stdout):toEqual 'say "hi" 1\r\n'
		end
	end)
end)

return nil
