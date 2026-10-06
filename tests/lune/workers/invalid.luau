--!strict

local Lune = require "../../../src/lune"
local Common = require "./common"

local batch = Common.produce()
Common.writeFile(
	Common.args[2],
	Lune.runtime.json.encode {
		receiptVersion = 1,
		runId = Common.args[3],
		batchId = batch.id,
		report = { total = "many" },
	}
)
