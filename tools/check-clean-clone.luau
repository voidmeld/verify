--!strict
local Checks = require "../src/checks"
local Config = require "./checks-config"
local Finish = require "./lib/check-result"
Finish("check-clean-clone", Checks.cleanClone(Config.cleanClone))
