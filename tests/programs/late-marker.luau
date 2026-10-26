--!strict

local fs = require "@std/fs"
local process = require "@std/process"
local task = require "@std/task"

local path = assert(process.args[2], "late-marker needs a path")
local seconds = assert(tonumber(process.args[3]), "late-marker needs a delay")
task.wait(seconds)
fs.writeStringToFile(path, "late")
