--!strict
local Checks = require "../src/checks"
local Config = require "./checks-config"
local Finish = require "./lib/check-result"
Finish("check-public-surface", Checks.publicSurface(Config.publicSurface))
