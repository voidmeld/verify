--!strict

local Store = require "../../src/lute/evidence-store"
local Shared = require "./shared"

Shared.run { name = "lute", sha256 = Store.sha256 }
