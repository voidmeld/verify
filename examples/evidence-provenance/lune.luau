--!strict

local load = require :: (string) -> unknown
local serde = load "@lune/serde" :: { hash: (algorithm: string, message: string) -> string }
local Shared = require "./shared"

Shared.run {
	name = "lune",
	sha256 = function(bytes: string): string
		return serde.hash("sha256", bytes)
	end,
}
