--!strict

local process = require "@std/process"
local Core = require "../src/core"
local OpenCloud = require "../src/lute/open-cloud"
local Platform = require "../src/lute/platform"

local options: Platform.Options =
	{ host = "simulator", entry = "", frameworkDirectory = process.args[1]:match "^(.*)/tools/run%.luau$" or "." }
local ids: { string } = {}
local roots: { string } = {}
local media: { string } = {}
type Supplied = { request: OpenCloud.Transport, authorize: (OpenCloud.Call) -> OpenCloud.Authorization }
local cloudModule: string? = nil
local cloudTarget: { universe: string?, place: string?, version: string? } = {}
local index = 2
while index <= #process.args do
	local flag = process.args[index]
	if flag == "--capture" then
		options.finalCapture = true
	else
		local value = assert(process.args[index + 1], "missing value for " .. flag)
		index += 1
		if flag == "--host" then
			assert(
				value == "simulator" or value == "studio" or value == "player" or value == "open-cloud",
				"unknown host"
			)
			options.host = value
		elseif flag == "--entry" then
			options.entry = value
		elseif flag == "--case" then
			table.insert(ids, value)
		elseif flag == "--root" then
			table.insert(roots, value)
		elseif flag == "--output" then
			options.output = value
		elseif flag == "--framework" then
			options.frameworkDirectory = value
		elseif flag == "--place" then
			options.place = value
		elseif flag == "--base-place" then
			options.basePlace = value
		elseif flag == "--place-id" then
			options.placeId = assert(tonumber(value), "invalid place id")
			cloudTarget.place = value
		elseif flag == "--cloud" then
			cloudModule = value
		elseif flag == "--universe-id" then
			cloudTarget.universe = value
		elseif flag == "--place-version" then
			cloudTarget.version = value
		elseif flag == "--deadline" then
			options.deadlineSeconds = assert(tonumber(value), "invalid deadline")
		elseif flag == "--players" then
			options.players = assert(tonumber(value), "invalid player count")
		elseif flag == "--client" then
			options.clientEntry = value
		elseif flag == "--server" then
			options.serverEntry = value
		elseif flag == "--require-media" then
			table.insert(media, value)
		elseif flag == "--context" then
			assert(value == "Server" or value == "Client", "invalid context")
			options.context = value
		else
			error("unknown option " .. flag)
		end
	end
	index += 1
end
assert(
	options.entry ~= "",
	"usage: lute run tools/run.luau --entry <module.luau> [--host simulator|studio|player|open-cloud] [--case id]"
)
if options.host == "open-cloud" then
	local universe, place, version = cloudTarget.universe, cloudTarget.place, cloudTarget.version
	assert(
		cloudModule ~= nil and universe ~= nil and place ~= nil and version ~= nil,
		"open-cloud requires --cloud module, --universe-id, --place-id and --place-version"
	)
	local supplied = (require("../" .. string.gsub(cloudModule, "%.luau$", "")) :: unknown) :: Supplied
	options.cloud = {
		universeId = universe,
		placeId = place,
		versionId = version,
		request = supplied.request,
		authorize = supplied.authorize,
	}
end
options.caseIds = if #ids > 0 then ids else nil
options.roots = roots
options.requiredMedia = media
local result = Platform.run(options)
print(Core.format(result.report))
print("Evidence: " .. result.directory)
if result.cloud ~= nil then
	local timing = result.cloud.timing
	print(
		("Open Cloud: delivery=%s state=%s task=%s submit=%ss poll=%ss total=%ss polls=%d"):format(
			result.cloud.delivery,
			tostring(result.cloud.state),
			if result.cloud.handle ~= nil then result.cloud.handle.path else "none",
			if timing.submitSeconds ~= nil then ("%.3f"):format(timing.submitSeconds) else "n/a",
			("%.3f"):format(timing.pollSeconds),
			("%.3f"):format(timing.totalSeconds),
			timing.polls
		)
	)
end
if result.report.total == 0 or result.report.passed ~= result.report.total then
	process.exit(1)
end
