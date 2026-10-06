--!strict

local Console = require "../core/console"

export type Window = {
	pid: number,
	id: number,
	layer: number,
	width: number,
	height: number,
	owner: string,
}

export type Refusal = { ok: false, reason: string, detail: string }

export type Selection = { ok: true, window: Window } | Refusal

export type WindowList = { ok: true, rows: { Window } } | Refusal

export type ViewportTarget = { width: number, height: number }

export type ViewportRect = { x: number, y: number, width: number, height: number }

export type CropOutcome = { ok: true, rect: ViewportRect } | Refusal

export type Frame =
	{ ok: true, path: string, width: number, height: number, bytes: number, viewportRect: ViewportRect? }
	| Refusal

export type CaptureDeps = {
	windowList: () -> WindowList,
	hostPids: () -> { number },
	capture: (windowId: number, outPath: string) -> (boolean, string),
	cropToViewport: (windowPngPath: string, outPath: string, target: ViewportTarget) -> CropOutcome,
	cropToRect: (windowPngPath: string, outPath: string, rect: ViewportRect) -> CropOutcome,
	readFrame: (path: string) -> string?,
}

export type CaptureReasons = {
	notHost: string,
	windowListFailed: string,
	noWindow: string,
	captureFailed: string,
	frameMissing: string,
	frameThin: string,
	frameNotPng: string,
}

export type CaptureLimits = {
	minimumBytes: number,
	minimumEdge: number,
	documentLayer: number,
}

export type CaptureOptions = {
	pid: number,
	windowId: number?,
	outPath: string,
	deps: CaptureDeps,
	reasons: CaptureReasons,
	limits: CaptureLimits?,
	viewport: ViewportTarget?,
	rect: ViewportRect?,
}

local DEFAULT_LIMITS: CaptureLimits = table.freeze {
	minimumBytes = 50 * 1024,
	minimumEdge = 200,
	documentLayer = 0,
}

local DEFAULT_REASONS: CaptureReasons = table.freeze {
	notHost = "window_capture_not_host",
	windowListFailed = "window_capture_window_list_failed",
	noWindow = "window_capture_no_window",
	captureFailed = "window_capture_failed",
	frameMissing = "window_capture_frame_missing",
	frameThin = "window_capture_frame_thin",
	frameNotPng = "window_capture_frame_not_png",
}

local PNG_MAGIC = "\137PNG\r\n\26\n"

local function refuse(reason: string, detail: string): Refusal
	return { ok = false, reason = reason, detail = detail }
end

local function parseWindowRows(text: string): { Window }
	local rows: { Window } = {}
	for line in string.gmatch(text, "[^\r\n]+") do
		local pid, id, layer, width, height, owner =
			string.match(line, "^(%-?%d+)\t(%-?%d+)\t(%-?%d+)\t(%-?%d+)\t(%-?%d+)\t(.*)$")
		if pid ~= nil then
			table.insert(rows, {
				pid = tonumber(pid) :: number,
				id = tonumber(id) :: number,
				layer = tonumber(layer) :: number,
				width = tonumber(width) :: number,
				height = tonumber(height) :: number,
				owner = owner :: string,
			})
		end
	end
	return rows
end

local function selectWindow(
	rows: { Window },
	pid: number,
	reasons: CaptureReasons?,
	limits: CaptureLimits?,
	windowId: number?
): Selection
	local named = if reasons ~= nil then reasons else DEFAULT_REASONS
	local bounds = if limits ~= nil then limits else DEFAULT_LIMITS
	local owned = 0
	local best: Window? = nil
	for _, row in rows do
		if row.pid == pid then
			owned += 1
			if
				(windowId == nil or row.id == windowId)
				and row.layer == bounds.documentLayer
				and row.width >= bounds.minimumEdge
				and row.height >= bounds.minimumEdge
			then
				local current = best
				if current == nil then
					best = row
				else
					local area = row.width * row.height
					local bestArea = current.width * current.height
					if area > bestArea or (area == bestArea and row.id < current.id) then
						best = row
					end
				end
			end
		end
	end
	local chosen = best
	if chosen == nil then
		if owned == 0 then
			return refuse(named.noWindow, ("no on-screen window belongs to pid %d"):format(pid))
		end
		return refuse(
			named.noWindow,
			("pid %d owns %d on-screen window(s), none of them a document window at least %dx%d"):format(
				pid,
				owned,
				bounds.minimumEdge,
				bounds.minimumEdge
			)
		)
	end
	return { ok = true, window = chosen }
end

local function pngSize(bytes: string): (number?, number?)
	if #bytes < 24 or string.sub(bytes, 1, 8) ~= PNG_MAGIC or string.sub(bytes, 13, 16) ~= "IHDR" then
		return nil, nil
	end
	local function be32(offset: number): number
		local value = 0
		for index = offset, offset + 3 do
			value = value * 256 + string.byte(bytes, index)
		end
		return value
	end
	return be32(17), be32(21)
end

local function parsePid(value: string?): number?
	if value == nil or string.match(value, "^%d+$") == nil then
		return nil
	end
	local pid = tonumber(value)
	if pid == nil or pid <= 0 then
		return nil
	end
	return pid
end

local function ownedByHost(pid: number, deps: CaptureDeps): ({ string }, boolean)
	local names: { string } = {}
	local owned = false
	for _, candidate in deps.hostPids() do
		table.insert(names, tostring(candidate))
		if candidate == pid then
			owned = true
		end
	end
	return names, owned
end

local function documentWindowSize(
	pid: number,
	deps: CaptureDeps,
	reasons: CaptureReasons?,
	limits: CaptureLimits?,
	windowId: number?
): (number?, number?, string?)
	local named = if reasons ~= nil then reasons else DEFAULT_REASONS
	local _, owned = ownedByHost(pid, deps)
	if not owned then
		return nil, nil, named.notHost
	end
	local listed = deps.windowList()
	if not listed.ok then
		return nil, nil, listed.reason
	end
	local selection = selectWindow(listed.rows, pid, named, limits, windowId)
	if not selection.ok then
		return nil, nil, selection.reason
	end
	return selection.window.width, selection.window.height, nil
end

local function captureFrame(options: CaptureOptions): Frame
	local deps = options.deps
	local reasons = options.reasons
	local limits = if options.limits ~= nil then options.limits else DEFAULT_LIMITS
	local pid = options.pid
	local outPath = options.outPath

	local names, owned = ownedByHost(pid, deps)
	if not owned then
		return refuse(
			reasons.notHost,
			("pid %d is not one of the host processes (%s)"):format(
				pid,
				if #names == 0 then "none running" else table.concat(names, ", ")
			)
		)
	end

	local listed = deps.windowList()
	if not listed.ok then
		return refuse(listed.reason, listed.detail)
	end
	local selection = selectWindow(listed.rows, pid, reasons, limits, options.windowId)
	if not selection.ok then
		return refuse(selection.reason, selection.detail)
	end
	local window = selection.window

	local viewportRect: ViewportRect? = nil
	if options.rect == nil and options.viewport == nil then
		local captured, detail = deps.capture(window.id, outPath)
		if not captured then
			return refuse(reasons.captureFailed, detail)
		end
	else
		local windowPath = outPath .. ".window.png"
		local captured, detail = deps.capture(window.id, windowPath)
		if not captured then
			return refuse(reasons.captureFailed, detail)
		end
		local cropped = if options.rect ~= nil
			then deps.cropToRect(windowPath, outPath, options.rect :: ViewportRect)
			else deps.cropToViewport(windowPath, outPath, options.viewport :: ViewportTarget)
		if not cropped.ok then
			return refuse(cropped.reason, cropped.detail)
		end
		viewportRect = cropped.rect
	end

	local bytes = deps.readFrame(outPath)
	if bytes == nil then
		return refuse(reasons.frameMissing, ("nothing was written to %s"):format(outPath))
	end
	if string.sub(bytes, 1, 8) ~= PNG_MAGIC then
		return refuse(reasons.frameNotPng, ("%s does not begin with the PNG signature"):format(outPath))
	end
	if #bytes < limits.minimumBytes then
		return refuse(
			reasons.frameThin,
			("%s is %d bytes, under the %d a real frame carries"):format(outPath, #bytes, limits.minimumBytes)
		)
	end
	local width, height = pngSize(bytes)
	if width == nil or height == nil then
		return refuse(reasons.frameNotPng, ("%s carries no readable IHDR"):format(outPath))
	end
	return {
		ok = true,
		path = outPath,
		width = width :: number,
		height = height :: number,
		bytes = #bytes,
		viewportRect = viewportRect,
	}
end

export type ChangeDeps = {
	isAncestor: (string, string) -> boolean,
	changedPaths: (string, string) -> { string },
}

export type ChangeReasons = {
	notAncestor: string,
	changed: string,
}

local DEFAULT_CHANGE_REASONS: ChangeReasons = table.freeze {
	notAncestor = "sha_not_ancestor",
	changed = "subject_changed_since_capture",
}

local function changedPathArgs(fromSha: string, toSha: string, excludedPaths: { string }): { string }
	local args: { string } = { "git", "diff", "--name-only", fromSha, toSha, "--", "." }
	for _, excluded in excludedPaths do
		table.insert(args, ":(exclude)" .. excluded)
	end
	return args
end

local function acceptsChange(
	recordedSha: string,
	candidateSha: string,
	deps: ChangeDeps,
	reasons: ChangeReasons?
): (boolean, string?, string?)
	local named = if reasons ~= nil then reasons else DEFAULT_CHANGE_REASONS
	if recordedSha == candidateSha then
		return true, nil, nil
	end
	if not deps.isAncestor(recordedSha, candidateSha) then
		return false, named.notAncestor, ("recorded %s wanted %s"):format(recordedSha, candidateSha)
	end
	local changed = deps.changedPaths(recordedSha, candidateSha)
	if #changed > 0 then
		return false, named.changed, table.concat(changed, "\n")
	end
	return true, nil, nil
end

export type CheckpointFrame = {
	checkpoint: string,
	path: string,
	sha256: string,
	bytes: number,
	width: number,
	height: number,
}

export type CheckpointFramesOptions = {
	frames: unknown,
	checkpoints: { string },
	framePath: (checkpoint: string) -> string,
	wholeWindowTolerance: number?,
	requireDistinctFrames: boolean?,
}

local DEFAULT_WHOLE_WINDOW_TOLERANCE = 0.10

local function isDigest(value: unknown): boolean
	return type(value) == "string" and #value == 64 and string.match(value, "^[0-9a-f]+$") ~= nil
end

local function positiveInteger(value: unknown): boolean
	return type(value) == "number" and value > 0 and value % 1 == 0
end

local function looksLikeWholeWindow(
	width: number,
	height: number,
	windowWidth: number,
	windowHeight: number,
	tolerance: number?,
	pixelScale: number?
): boolean
	local scale = pixelScale or 1
	if scale <= 0 or scale ~= scale or scale == math.huge then
		error("window pixel scale must be finite and positive", 2)
	end
	windowWidth *= scale
	windowHeight *= scale
	local within = if tolerance ~= nil then tolerance else DEFAULT_WHOLE_WINDOW_TOLERANCE
	return math.abs(width - windowWidth) / windowWidth < within
		and math.abs(height - windowHeight) / windowHeight < within
end

local function checkpointFrames(options: CheckpointFramesOptions): ({ CheckpointFrame }?, string?)
	local rawFrames = options.frames
	if type(rawFrames) ~= "table" then
		return nil, "frame_missing: observation carries no frames"
	end
	local byCheckpoint: { [string]: { [string]: unknown } } = {}
	for _, row in rawFrames :: { unknown } do
		if type(row) == "table" and type((row :: { [string]: unknown }).checkpoint) == "string" then
			if byCheckpoint[(row :: { [string]: string }).checkpoint] ~= nil then
				return nil, "frame_duplicate_checkpoint: " .. (row :: { [string]: string }).checkpoint
			end
			byCheckpoint[(row :: { [string]: string }).checkpoint] = row :: { [string]: unknown }
		end
	end
	local ordered: { CheckpointFrame } = {}
	local byDigest: { [string]: string } = {}
	for _, name in options.checkpoints do
		local row = byCheckpoint[name]
		if row == nil then
			return nil, "frame_missing: " .. name
		end
		if
			row.path ~= options.framePath(name)
			or not isDigest(row.sha256)
			or not positiveInteger(row.bytes)
			or not positiveInteger(row.width)
			or not positiveInteger(row.height)
			or not positiveInteger(row.windowWidth)
			or not positiveInteger(row.windowHeight)
			or (
				row.windowPixelScale :: number? ~= nil
				and (
					type(row.windowPixelScale) ~= "number"
					or row.windowPixelScale <= 0
					or row.windowPixelScale ~= row.windowPixelScale
					or row.windowPixelScale == math.huge
				)
			)
		then
			return nil, "frame_missing: " .. name
		end
		if
			looksLikeWholeWindow(
				row.width :: number,
				row.height :: number,
				row.windowWidth :: number,
				row.windowHeight :: number,
				options.wholeWindowTolerance,
				row.windowPixelScale :: number?
			)
		then
			return nil, "frame_not_viewport: " .. name
		end
		if options.requireDistinctFrames and byDigest[row.sha256 :: string] ~= nil then
			return nil, "frame_reused: " .. name .. " duplicates " .. byDigest[row.sha256 :: string]
		end
		byDigest[row.sha256 :: string] = name
		table.insert(ordered, {
			checkpoint = name,
			path = row.path :: string,
			sha256 = row.sha256 :: string,
			bytes = row.bytes :: number,
			width = row.width :: number,
			height = row.height :: number,
		})
	end
	return ordered, nil
end

export type CaptureRecord = {
	kind: string,
	target: string,
	sourceSha: string,
	recordedAtUnix: number,
	consoleSha256: string,
	consoleErrorLines: { string },
	screenshotSha256: string,
	screenshotBytes: number,
}

export type RecordOutcome = {
	ok: boolean,
	reason: string,
	detail: string?,
	record: (CaptureRecord & { validForRange: { from: string, to: string }? })?,
}

export type RecordOptions = {
	kind: string,
	target: string,
	console: string?,
	screenshot: string?,
	sourceSha: string?,
	recordedAtUnix: number,
	sha256: (string) -> string,
	classify: Console.ClassifyOptions,
	windowBounds: { width: number, height: number, pixelScale: number? }?,
	wholeWindowTolerance: number?,
}

local function refusal(reason: string, detail: string?): RecordOutcome
	return { ok = false, reason = reason, detail = detail }
end

local function isCommitSha(value: unknown): boolean
	return type(value) == "string" and #value == 40 and string.match(value, "^[0-9a-f]+$") ~= nil
end

local function isTarget(value: unknown): boolean
	return type(value) == "string" and value ~= "" and string.match(value, "^[%w_%-]+$") ~= nil
end

local function recordCapture(options: RecordOptions): RecordOutcome
	if not isTarget(options.target) then
		return refusal("target_invalid", tostring(options.target))
	end
	if options.console == nil then
		return refusal("console_unreadable", options.target)
	end
	if options.screenshot == nil then
		return refusal("screenshot_unreadable", options.target)
	end
	local bounds = options.windowBounds
	if bounds ~= nil then
		local scale = bounds.pixelScale
		if scale ~= nil and (scale <= 0 or scale ~= scale or scale == math.huge) then
			return refusal("window_scale_invalid", tostring(scale))
		end
		local shotWidth, shotHeight = pngSize(options.screenshot :: string)
		if
			shotWidth ~= nil
			and shotHeight ~= nil
			and looksLikeWholeWindow(
				shotWidth :: number,
				shotHeight :: number,
				bounds.width,
				bounds.height,
				options.wholeWindowTolerance,
				bounds.pixelScale
			)
		then
			return refusal(
				"frame_not_viewport",
				("%s is %dx%d, the whole document window (%dx%d host units) rather than a cropped viewport"):format(
					options.target,
					shotWidth :: number,
					shotHeight :: number,
					bounds.width,
					bounds.height
				)
			)
		end
	end
	if not isCommitSha(options.sourceSha) then
		return refusal("sha_invalid", tostring(options.sourceSha))
	end
	local record: CaptureRecord = {
		kind = options.kind,
		target = options.target,
		sourceSha = options.sourceSha :: string,
		recordedAtUnix = options.recordedAtUnix,
		consoleSha256 = options.sha256(options.console :: string),
		consoleErrorLines = Console.classifyConsoleText(options.console :: string, options.classify),
		screenshotSha256 = options.sha256(options.screenshot :: string),
		screenshotBytes = #(options.screenshot :: string),
	}
	return {
		ok = true,
		reason = "capture_recorded",
		record = (record :: unknown) :: CaptureRecord & { validForRange: { from: string, to: string }? },
	}
end

local RECORD_FIELDS: { [string]: boolean } = {
	kind = true,
	target = true,
	sourceSha = true,
	recordedAtUnix = true,
	consoleSha256 = true,
	consoleErrorLines = true,
	screenshotSha256 = true,
	screenshotBytes = true,
}

local function exactKeys(value: unknown): boolean
	if type(value) ~= "table" or ((getmetatable :: unknown) :: (unknown) -> unknown)(value) ~= nil then
		return false
	end
	for key in value :: { [unknown]: unknown } do
		if type(key) == "string" and RECORD_FIELDS[key] ~= true then
			return false
		elseif type(key) ~= "string" and type(key) ~= "userdata" then
			return false
		end
	end
	return true
end

local function isDigestField(value: unknown): boolean
	return isDigest(value)
end

local function decodeCapture(value: unknown, kind: string, target: string): (CaptureRecord?, string?)
	if not exactKeys(value) then
		return nil, "capture_record_invalid"
	end
	local record = value :: { [string]: unknown }
	if
		record.kind ~= kind
		or record.target ~= target
		or not isCommitSha(record.sourceSha)
		or type(record.recordedAtUnix) ~= "number"
		or not isDigestField(record.consoleSha256)
		or not isDigestField(record.screenshotSha256)
		or type(record.screenshotBytes) ~= "number"
		or record.screenshotBytes % 1 ~= 0
		or record.screenshotBytes < 0
		or type(record.consoleErrorLines) ~= "table"
	then
		return nil, "capture_record_invalid"
	end
	for key, line in record.consoleErrorLines :: { [unknown]: unknown } do
		if (type(key) ~= "number" and type(key) ~= "userdata") or type(line) ~= "string" then
			return nil, "capture_record_invalid"
		end
	end
	return (record :: unknown) :: CaptureRecord, nil
end

export type CheckCaptureOptions = {
	record: CaptureRecord,
	candidateSha: string,
	changeDeps: ChangeDeps,
	changeReasons: ChangeReasons?,
}

local function checkCapture(options: CheckCaptureOptions): RecordOutcome
	local record = options.record
	if not isCommitSha(options.candidateSha) then
		return refusal("sha_invalid", tostring(options.candidateSha))
	end
	local fresh, staleReason, staleDetail =
		acceptsChange(record.sourceSha, options.candidateSha, options.changeDeps, options.changeReasons)
	if not fresh then
		return refusal(staleReason :: string, record.target .. " " .. (staleDetail :: string))
	end
	if record.screenshotBytes <= 0 then
		return refusal("screenshot_empty", record.target)
	end
	if #record.consoleErrorLines > 0 then
		return refusal("console_red", table.concat(record.consoleErrorLines, "\n"))
	end
	local verified = table.clone(record) :: CaptureRecord & { validForRange: { from: string, to: string }? }
	verified.validForRange = { from = record.sourceSha, to = options.candidateSha }
	return { ok = true, reason = "capture_verified", record = verified }
end

return {
	DEFAULT_CAPTURE_LIMITS = DEFAULT_LIMITS,
	DEFAULT_CAPTURE_REASONS = DEFAULT_REASONS,
	DEFAULT_CHANGE_REASONS = DEFAULT_CHANGE_REASONS,
	DEFAULT_WHOLE_WINDOW_TOLERANCE = DEFAULT_WHOLE_WINDOW_TOLERANCE,
	parseWindowRows = parseWindowRows,
	selectWindow = selectWindow,
	pngSize = pngSize,
	parsePid = parsePid,
	documentWindowSize = documentWindowSize,
	captureFrame = captureFrame,
	changedPathArgs = changedPathArgs,
	acceptsChange = acceptsChange,
	looksLikeWholeWindow = looksLikeWholeWindow,
	checkpointFrames = checkpointFrames,
	recordCapture = recordCapture,
	decodeCapture = decodeCapture,
	checkCapture = checkCapture,
}
