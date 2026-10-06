--!strict

local Lune = require "../../../src/lune"
local Common = require "./common"

local batch, report = Common.produce()
Common.writeFile(Common.args[2], Lune.encodeReceipt(Lune.runtime.json, "another-run", batch.id, report))
