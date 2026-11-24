--!strict
local Checks = require "../src/checks"
local Finish = require "./lib/check-result"
Finish("type policy", Checks.noAny { untracked = true })
