--!strict

local fs = require "@std/fs"
local process = require "@std/process"

local source = assert(process.args[2], "copy needs a source")
local target = assert(process.args[3], "copy needs a target")
fs.writeStringToFile(target, fs.readFileToString(source))
