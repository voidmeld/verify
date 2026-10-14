--!strict

local io = require "@std/io"
local process = require "@std/process"

local code = assert(tonumber(process.args[2]), "exit-with needs an exit code")
for index = 3, #process.args do
	io.write("[" .. process.args[index] .. "]")
end
process.exit(code)
