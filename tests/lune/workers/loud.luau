--!strict

local Lune = require "../../../src/lune"
local Common = require "./common"

print "worker-says-hello"
Lune.worker(Common.operations)
