--!strict

local process = require "@std/process"
local Studio = require "../src/lute/studio"
assert(process.args[2] ~= nil, "expected native run request")
Studio.worker(process.args[2])
