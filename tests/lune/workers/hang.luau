--!strict

local Common = require "./common"

local survivor = Common.args[2] .. ".survivor"
if Common.os == "windows" then
	Common.exec("cmd", {
		"/c",
		("start /b lute run tests/programs/late-marker.luau %s 4 & ping -n 31 127.0.0.1 >nul"):format(survivor),
	})
else
	Common.exec("/bin/sh", { "-c", "(sleep 4; echo survived > " .. survivor .. ") & sleep 30" })
end
