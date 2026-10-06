--!strict

local Common = require "./common"

Common.exec("/bin/sh", { "-c", "(sleep 4; echo survived > " .. Common.args[2] .. ".survivor) & sleep 30" })
