--!strict

local ENTITIES: { [string]: string } = { lt = "<", gt = ">", amp = "&", quot = '"', apos = "'" }

local function plain(text: string): string
	local source = string.gsub(text, "<!%-%-.-%-%->", "")
	source = string.gsub(source, "</?%a+.->", function(tag: string): string
		return if string.lower(tag):match "^<br[%s/>]" then "\n" else ""
	end)
	return (string.gsub(source, "&(%a+);", function(name: string): string
		return ENTITIES[name] or `&{name};`
	end))
end

return { plain = plain }
