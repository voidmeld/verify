--!strict

local Lune = require "../../../src/lune"
local Common = require "./common"

local _, report = Common.produce()
Common.writeFile(Common.args[2], Lune.encode(report))
