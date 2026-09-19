--!strict

local crypto = require "@lute/crypto"
local fs = require "@std/fs"
local json = require "@std/json"
local process = require "@std/process"
local Files = require "./files"

export type Options = {
	packageRoot: string,
	cacheDirectory: string,
	imagePath: string,
	capabilities: { string },
	logicalWidth: number?,
	logicalHeight: number?,
	markerSize: number?,
	inspect: boolean?,
}
export type Outcome = { status: "complete" | "held" | "unsupported", reason: string, data: any? }

local CAPABILITY = "macos-image-processing"
local function digest(bytes: string): string
	local value = crypto.digest(crypto.hash.sha256, bytes)
	local out: { string } = {}
	for index = 0, buffer.len(value) - 1 do
		table.insert(out, string.format("%02x", buffer.readu8(value, index)))
	end
	return table.concat(out)
end

local function detect(options: Options): Outcome
	if table.find(options.capabilities, CAPABILITY) == nil then
		return { status = "unsupported", reason = "missing_capability:" .. CAPABILITY }
	end
	if not fs.exists "/System/Library/CoreServices/SystemVersion.plist" then
		return { status = "unsupported", reason = "macos_image_processing_unavailable" }
	end
	local source = options.packageRoot .. "/src/lute/viewport-corners.swift"
	if not fs.exists(source) or not fs.exists(options.imagePath) then
		return { status = "held", reason = "corner_detector_input_missing" }
	end
	if not options.inspect then
		for _, key in { "logicalWidth", "logicalHeight" } do
			local dimension = (options :: any)[key]
			if type(dimension) ~= "number" or dimension <= 0 or dimension % 1 ~= 0 then
				return { status = "held", reason = "corner_detector_dimensions_invalid" }
			end
		end
	end
	local markerSize = options.markerSize or 6
	if
		type(markerSize) ~= "number"
		or markerSize <= 0
		or markerSize % 1 ~= 0
		or (
			not options.inspect
			and (markerSize >= (options.logicalWidth :: number) or markerSize >= (options.logicalHeight :: number))
		)
	then
		return { status = "held", reason = "corner_detector_marker_size_invalid" }
	end
	local sourceBytes = fs.readFileToString(source)
	local binary = options.cacheDirectory .. "/viewport-corners-" .. digest(sourceBytes)
	if not fs.exists(binary) then
		local owned = Files.claimDirectory(options.cacheDirectory .. "/compile")
		local candidate = owned .. "/detector"
		local frozenSource = owned .. "/detector.swift"
		local installed, problem: any = pcall(function(): string?
			fs.writeStringToFile(frozenSource, sourceBytes)
			local compiled = process.run { "/usr/bin/swiftc", "-O", "-o", candidate, frozenSource }
			if not compiled.ok then
				return "corner_detector_compile_failed:" .. compiled.stderr
			end
			local moved, moveProblem: any = pcall(fs.move, candidate, binary)
			if not moved and not fs.exists(binary) then
				return "corner_detector_install_failed:" .. tostring(moveProblem)
			end
			return nil
		end)
		Files.removeIfPresent(candidate)
		Files.removeIfPresent(frozenSource)
		pcall(fs.removeDirectory, owned)
		if not installed or problem ~= nil then
			return {
				status = "held",
				reason = if installed then problem else "corner_detector_prepare_failed:" .. tostring(problem),
			}
		end
	end
	local argv = if options.inspect
		then { binary, options.imagePath, "--inspect" }
		else {
			binary,
			options.imagePath,
			tostring(options.logicalWidth),
			tostring(options.logicalHeight),
			tostring(markerSize),
		}
	local ran = process.run(argv)
	if not ran.ok then
		return { status = "held", reason = "corner_detector_refused:" .. ran.stderr }
	end
	local ok, data: any = pcall(json.deserialize, ran.stdout)
	if not ok or type(data) ~= "table" then
		return { status = "held", reason = "corner_detector_output_invalid" }
	end
	return { status = "complete", reason = "corner_geometry_observed", data = data }
end

return { CAPABILITY = CAPABILITY, detect = detect }
