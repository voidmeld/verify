--!strict

local Verify = require "../src/core"

local Lute = require "../src/lute"
local WindowCapture = Lute.windowCapture

local HOST_PID = 4242

local REASONS: Lute.WindowCaptureReasons = {
	notHost = "frame_not_host",
	windowListFailed = "frame_window_list_failed",
	noWindow = "frame_no_window",
	captureFailed = "frame_capture_failed",
	frameMissing = "frame_missing",
	frameThin = "frame_thin",
	frameNotPng = "frame_not_png",
}

local function pngBytes(width: number, height: number, size: number): string
	local function be32(value: number): string
		return string.char(
			bit32.band(bit32.rshift(value, 24), 255),
			bit32.band(bit32.rshift(value, 16), 255),
			bit32.band(bit32.rshift(value, 8), 255),
			bit32.band(value, 255)
		)
	end
	local header = "\137PNG\r\n\26\n" .. be32(13) .. "IHDR" .. be32(width) .. be32(height)
	return header .. string.rep("\0", math.max(0, size - #header))
end

type WindowPatch = { pid: number?, id: number?, layer: number?, width: number?, height: number?, owner: string? }
local function window(overrides: WindowPatch): Lute.WindowCaptureWindow
	return {
		pid = overrides.pid or HOST_PID,
		id = overrides.id or 7,
		layer = if overrides.layer ~= nil then overrides.layer else 0,
		width = overrides.width or 1440,
		height = overrides.height or 900,
		owner = overrides.owner or "Editor",
	}
end

type Recorder = {
	captured: { { id: number, path: string } },
	cropped: { { path: string, target: Lute.WindowCaptureViewportTarget } },
	rectCropped: { { path: string, rect: Lute.WindowCaptureViewportRect } },
}

type CaptureFixture = {
	listFailure: Lute.WindowCaptureList?,
	rows: { Lute.WindowCaptureWindow }?,
	pids: { number }?,
	captureOk: boolean?,
	captureDetail: string?,
	cropOutcome: Lute.WindowCaptureCropOutcome?,
	rectCropOutcome: Lute.WindowCaptureCropOutcome?,
	file: string?,
}
local function deps(overrides: CaptureFixture): (Lute.WindowCaptureDeps, Recorder)
	local recorder: Recorder = { captured = {}, cropped = {}, rectCropped = {} }
	local bound: Lute.WindowCaptureDeps = {
		windowList = function(): Lute.WindowCaptureList
			if overrides.listFailure ~= nil then
				return overrides.listFailure
			end
			return { ok = true, rows = overrides.rows or { window {} } }
		end,
		hostPids = function(): { number }
			return overrides.pids or { HOST_PID }
		end,
		capture = function(id: number, path: string): (boolean, string)
			table.insert(recorder.captured, { id = id, path = path })
			if overrides.captureOk == false then
				return false, overrides.captureDetail or "capture refused"
			end
			return true, ""
		end,
		cropToViewport = function(
			_from: string,
			_to: string,
			target: Lute.WindowCaptureViewportTarget
		): Lute.WindowCaptureCropOutcome
			table.insert(recorder.cropped, { path = _to, target = target })
			return overrides.cropOutcome
				or { ok = true, rect = { x = 10, y = 20, width = target.width, height = target.height } }
		end,
		cropToRect = function(
			_from: string,
			_to: string,
			rect: Lute.WindowCaptureViewportRect
		): Lute.WindowCaptureCropOutcome
			table.insert(recorder.rectCropped, { path = _to, rect = rect })
			return overrides.rectCropOutcome or { ok = true, rect = rect }
		end,
		readFrame = function(_path: string): string?
			return overrides.file
		end,
	}
	return bound, recorder
end

type CapturePatch = {
	windowId: number?,
	rect: Lute.WindowCaptureViewportRect?,
	viewport: Lute.WindowCaptureViewportTarget?,
}
local function capture(overrides: CaptureFixture, extra: CapturePatch?): (Lute.WindowCaptureFrame, Recorder)
	local bound, recorder = deps(overrides)
	local options: Lute.WindowCaptureOptions = {
		pid = HOST_PID,
		outPath = "shots/frame.png",
		deps = bound,
		reasons = REASONS,
	}
	if extra ~= nil then
		options.windowId = extra.windowId
		options.rect = extra.rect
		options.viewport = extra.viewport
	end
	return WindowCapture.captureFrame(options), recorder
end

local function refused(outcome: Lute.WindowCaptureFrame): { ok: false, reason: string, detail: string }
	assert(not outcome.ok, "expected refusal")
	return outcome
end

return function(suite: Verify.Harness)
	suite:suite("explicit capture geometry", function()
		suite:case("captures the selected document even when another is larger", function(check)
			local outcome, recorder = capture(
				{ rows = { window { id = 7 }, window { id = 8, width = 2000 } }, file = pngBytes(1000, 600, 60000) },
				{ windowId = 7 }
			)
			check:expect(outcome.ok):toEqual(true)
			check:expect(recorder.captured[1].id):toEqual(7)
		end)

		suite:case("does not substitute a different document after the selected window disappears", function(check)
			local outcome, recorder = capture({ rows = { window { id = 8 } } }, { windowId = 7 })
			check:expect(outcome.ok):toEqual(false)
			check:expect(#recorder.captured):toEqual(0)
		end)

		suite:case("compares Retina pixels against explicitly scaled window points", function(check)
			check:expect((WindowCapture.looksLikeWholeWindow(2880, 1800, 1440, 900, nil, 2))):toEqual(true)
			check:expect((WindowCapture.looksLikeWholeWindow(1400, 800, 1440, 900, nil, 2))):toEqual(false)
			check:expect((WindowCapture.looksLikeWholeWindow(1440, 900, 1440, 900))):toEqual(true)
			check:expect((pcall(WindowCapture.looksLikeWholeWindow, 100, 100, 100, 100, nil, 0))):toEqual(false)
		end)
	end)

	suite:suite("window capture window capture", function()
		suite:case("parses only tab-separated window rows and drops the rest", function(check)
			local rows =
				WindowCapture.parseWindowRows "4242\t7\t0\t1440\t900\tEditor\nnoise line\n4242\t8\t3\t80\t20\tMenu\n"
			check:expect(#rows):toEqual(2)
			check:expect(rows[1].id):toEqual(7)
			check:expect(rows[1].owner):toEqual "Editor"
			check:expect(rows[2].layer):toEqual(3)
		end)

		suite:case("chooses the largest document-layer window and breaks ties on the lowest id", function(check)
			local rows = {
				window { id = 9, width = 800, height = 600 },
				window { id = 3, width = 1440, height = 900 },
				window { id = 2, width = 1440, height = 900 },
				window { id = 1, width = 4000, height = 3000, layer = 25 },
			}
			local selection = WindowCapture.selectWindow(rows, HOST_PID, REASONS)
			assert(selection.ok, "expected a window")
			check:expect(selection.window.id):toEqual(2)
		end)

		suite:case("refuses when the pid owns windows but none is a document window", function(check)
			local selection = WindowCapture.selectWindow({ window { layer = 25 } }, HOST_PID, REASONS)
			check
				:expect(refused(selection :: { ok: false, reason: string, detail: string }).reason)
				:toEqual "frame_no_window"
			assert(
				string.find(
					refused(selection :: { ok: false, reason: string, detail: string }).detail,
					"owns 1 on-screen window",
					1,
					true
				) ~= nil,
				"detail counts"
			)
		end)

		suite:case("refuses a pid the host does not own", function(check)
			local outcome = capture { pids = { 1, 2 } }
			check:expect(refused(outcome).reason):toEqual "frame_not_host"
		end)

		suite:case("saves the whole document window when neither viewport nor rect is given", function(check)
			local outcome, recorder = capture { file = pngBytes(1440, 900, 90 * 1024) }
			assert(outcome.ok, "expected a frame")
			check:expect(outcome.width):toEqual(1440)
			check:expect(outcome.viewportRect):toEqual(nil)
			check:expect(#recorder.cropped):toEqual(0)
			check:expect(recorder.captured[1].path):toEqual "shots/frame.png"
		end)

		suite:case("crops to an exact rect and never runs the aspect search", function(check)
			local rect = { x = 324, y = 222, width = 1065, height = 500 }
			local outcome, recorder = capture({ file = pngBytes(1065, 500, 90 * 1024) }, { rect = rect })
			assert(outcome.ok, "expected a frame")
			check:expect((outcome.viewportRect :: Lute.WindowCaptureViewportRect).width):toEqual(1065)
			check:expect(#recorder.cropped):toEqual(0)
			check:expect(#recorder.rectCropped):toEqual(1)
			check:expect(recorder.captured[1].path):toEqual "shots/frame.png.window.png"
		end)

		suite:case("prefers an explicit rect over a viewport target when both are given", function(check)
			local _, recorder = capture({ file = pngBytes(1065, 500, 90 * 1024) }, {
				viewport = { width = 844, height = 390 },
				rect = { x = 0, y = 0, width = 1065, height = 500 },
			})
			check:expect(#recorder.cropped):toEqual(0)
			check:expect(#recorder.rectCropped):toEqual(1)
		end)

		suite:case("asks the host cropper for an aspect match when only a viewport is given", function(check)
			local outcome, recorder = capture(
				{ file = pngBytes(844, 390, 90 * 1024) },
				{ viewport = { width = 844, height = 390 } }
			)
			assert(outcome.ok, "expected a frame")
			check:expect(#recorder.cropped):toEqual(1)
			check:expect(recorder.cropped[1].target.width):toEqual(844)
		end)

		suite:case("refuses a frame that is too thin, not a png, or missing", function(check)
			check:expect(refused((capture { file = pngBytes(1440, 900, 1024) })).reason):toEqual "frame_thin"
			check:expect(refused((capture { file = string.rep("x", 90 * 1024) })).reason):toEqual "frame_not_png"
			check:expect(refused((capture {})).reason):toEqual "frame_missing"
		end)

		suite:case("passes a cropper refusal through unchanged", function(check)
			local outcome = capture({
				file = pngBytes(844, 390, 90 * 1024),
				rectCropOutcome = { ok = false, reason = "viewport_unresolved", detail = "cropper refused" },
			}, { rect = { x = 0, y = 0, width = 10, height = 10 } })
			check:expect(refused(outcome).reason):toEqual "viewport_unresolved"
			check:expect(refused(outcome).detail):toEqual "cropper refused"
		end)

		suite:case("reports the document window size the capture would have used", function(check)
			local bound = deps { rows = { window { width = 1600, height = 1000 } } }
			local width, height, failure = WindowCapture.documentWindowSize(HOST_PID, bound, REASONS)
			check:expect(width):toEqual(1600)
			check:expect(height):toEqual(1000)
			check:expect(failure):toEqual(nil)
		end)

		suite:case("reads a pid only from a plain decimal string", function(check)
			check:expect(WindowCapture.parsePid "4242"):toEqual(4242)
			check:expect(WindowCapture.parsePid "-1"):toEqual(nil)
			check:expect(WindowCapture.parsePid "42a"):toEqual(nil)
			check:expect((WindowCapture.parsePid(nil))):toEqual(nil)
		end)
	end)

	suite:suite("window capture change freshness", function()
		local function changeDeps(ancestor: boolean, changed: { string }): Lute.WindowCaptureChangeDeps
			return {
				isAncestor = function(): boolean
					return ancestor
				end,
				changedPaths = function(): { string }
					return changed
				end,
			}
		end

		suite:case("accepts the identical revision without asking the host anything", function(check)
			local asked = false
			local ok = WindowCapture.acceptsChange("a", "a", {
				isAncestor = function(): boolean
					asked = true
					return false
				end,
				changedPaths = function(): { string }
					return {}
				end,
			})
			assert(ok, "expected acceptance")
			assert(not asked, "expected no ancestry question")
		end)

		suite:case("refuses a recorded revision that is not an ancestor of the candidate", function(check)
			local ok, reason = WindowCapture.acceptsChange("a", "b", changeDeps(false, {}))
			assert(not ok, "expected refusal")
			check:expect(reason):toEqual "sha_not_ancestor"
		end)

		suite:case("refuses when a watched path changed between the two revisions", function(check)
			local ok, reason, detail = WindowCapture.acceptsChange("a", "b", changeDeps(true, { "roblox/places/one" }))
			assert(not ok, "expected refusal")
			check:expect(reason):toEqual "subject_changed_since_capture"
			check:expect(detail):toEqual "roblox/places/one"
		end)

		suite:case("excludes exactly the paths the adopter supplies", function(check)
			local args = WindowCapture.changedPathArgs("a", "b", { "docs", "tools" })
			check:expect(args[#args - 1]):toEqual ":(exclude)docs"
			check:expect(args[#args]):toEqual ":(exclude)tools"
		end)
	end)

	suite:suite("window capture checkpoint frames", function()
		local function frame(overrides: {
			checkpoint: string,
			path: string?,
			sha256: string?,
			bytes: number?,
			width: number?,
			height: number?,
			windowWidth: number?,
			windowHeight: number?,
		}): { [string]: unknown }
			local row: { [string]: unknown } = {
				checkpoint = overrides.checkpoint,
				path = overrides.path or ("shots/" .. tostring(overrides.checkpoint) .. ".png"),
				sha256 = overrides.sha256 or string.rep("a", 64),
				bytes = overrides.bytes or 90000,
				width = overrides.width or 844,
				height = overrides.height or 390,
				windowWidth = overrides.windowWidth or 1440,
				windowHeight = overrides.windowHeight or 900,
			}
			return row
		end

		local function framePath(checkpoint: string): string
			return "shots/" .. checkpoint .. ".png"
		end

		suite:case("returns frames in the adopter's checkpoint order, not the array's", function(check)
			local ordered, failure = WindowCapture.checkpointFrames {
				frames = { frame { checkpoint = "arrival" }, frame { checkpoint = "boot" } },
				checkpoints = { "boot", "arrival" },
				framePath = framePath,
			}
			check:expect(failure):toEqual(nil)
			check:expect((ordered :: { Lute.WindowCaptureCheckpointFrame })[1].checkpoint):toEqual "boot"
			check:expect((ordered :: { Lute.WindowCaptureCheckpointFrame })[2].checkpoint):toEqual "arrival"
			check
				:expect(
					(((ordered :: { Lute.WindowCaptureCheckpointFrame })[1] :: unknown) :: { [string]: unknown }).windowWidth
				)
				:toEqual(nil)
		end)

		suite:case("refuses a missing checkpoint by name", function(check)
			local _, failure = WindowCapture.checkpointFrames {
				frames = { frame { checkpoint = "boot" } },
				checkpoints = { "boot", "arrival" },
				framePath = framePath,
			}
			check:expect(failure):toEqual "frame_missing: arrival"
		end)

		suite:case("refuses a frame saved anywhere but the derived path", function(check)
			local _, failure = WindowCapture.checkpointFrames {
				frames = { frame { checkpoint = "boot", path = "elsewhere.png" } },
				checkpoints = { "boot" },
				framePath = framePath,
			}
			check:expect(failure):toEqual "frame_missing: boot"
		end)

		suite:case("refuses a frame that is the whole window rather than a viewport", function(check)
			local _, failure = WindowCapture.checkpointFrames {
				frames = { frame { checkpoint = "boot", width = 1440, height = 900 } },
				checkpoints = { "boot" },
				framePath = framePath,
			}
			check:expect(failure):toEqual "frame_not_viewport: boot"
		end)

		suite:case("refuses duplicate checkpoint labels instead of selecting the last capture", function(check)
			local _, failure = WindowCapture.checkpointFrames {
				frames = { frame { checkpoint = "boot" }, frame { checkpoint = "boot", sha256 = string.rep("b", 64) } },
				checkpoints = { "boot" },
				framePath = framePath,
			}
			check:expect(failure):toEqual "frame_duplicate_checkpoint: boot"
		end)

		suite:case("refuses reused image bytes when distinct observations are required", function(check)
			local _, failure = WindowCapture.checkpointFrames {
				frames = { frame { checkpoint = "boot" }, frame { checkpoint = "arrival" } },
				checkpoints = { "boot", "arrival" },
				framePath = framePath,
				requireDistinctFrames = true,
			}
			check:expect(failure):toEqual "frame_reused: arrival duplicates boot"
		end)

		suite:case("accepts distinct observations under the strict capture policy", function(check)
			local frames, failure = WindowCapture.checkpointFrames {
				frames = {
					frame { checkpoint = "boot" },
					frame { checkpoint = "arrival", sha256 = string.rep("b", 64) },
				},
				checkpoints = { "boot", "arrival" },
				framePath = framePath,
				requireDistinctFrames = true,
			}
			check:expect(failure):toEqual(nil)
			check:expect(#(frames :: { Lute.WindowCaptureCheckpointFrame })):toEqual(2)
		end)

		suite:case("refuses observations carrying no frame table at all", function(check)
			local _, failure =
				WindowCapture.checkpointFrames { frames = nil, checkpoints = { "boot" }, framePath = framePath }
			check:expect(failure):toEqual "frame_missing: observation carries no frames"
		end)
	end)

	suite:suite("window capture records", function()
		local SHA = string.rep("1", 40)
		local KIND = "host.capture.v1"

		local function digest(value: string): string
			return string.sub(string.rep(tostring(#value), 64), 1, 64)
		end

		local function record(overrides: {
			target: string?,
			console: string?,
			screenshot: string?,
			sourceSha: string?,
			windowBounds: { width: number, height: number, pixelScale: number? }?,
			classify: Verify.ClassifyConsoleOptions?,
		}): Lute.CaptureRecordOutcome
			local options: Lute.CaptureRecordOptions = {
				kind = KIND,
				target = "fixture-target",
				console = "boot ok\n",
				screenshot = pngBytes(844, 390, 90 * 1024),
				sourceSha = SHA,
				recordedAtUnix = 1000,
				sha256 = digest,
				classify = { errorPatterns = { "attempt to", "refused" } },
			}
			if overrides.target ~= nil then
				options.target = overrides.target
			end
			if overrides.console ~= nil then
				options.console = overrides.console
			end
			if overrides.screenshot ~= nil then
				options.screenshot = overrides.screenshot
			end
			if overrides.sourceSha ~= nil then
				options.sourceSha = overrides.sourceSha
			end
			options.windowBounds = overrides.windowBounds
			if overrides.classify ~= nil then
				options.classify = overrides.classify
			end

			return WindowCapture.recordCapture(options)
		end

		suite:case("rejects a whole Retina window using the host supplied pixel scale", function(check)
			local outcome = record {
				screenshot = pngBytes(2880, 1800, 90000),
				windowBounds = { width = 1440, height = 900, pixelScale = 2 },
			}
			check:expect(outcome.ok):toEqual(false)
			check:expect(outcome.reason):toEqual "frame_not_viewport"
		end)

		suite:case("binds console classification, hashes and the clock the caller handed in", function(check)
			local outcome = record { console = "boot ok\nattempt to index nil\n" }
			assert(outcome.ok, "expected a capture record")
			local captured = assert(outcome.record)
			check:expect(captured.kind):toEqual(KIND)
			check:expect(captured.recordedAtUnix):toEqual(1000)
			check:expect(#captured.consoleErrorLines):toEqual(1)
			check:expect(captured.consoleErrorLines[1]):toEqual "attempt to index nil"
		end)

		suite:case("classifies through the adopter's own patterns and exclusions", function(check)
			local outcome = record {
				console = "BOOT FAILED at once\ntransport refused\n",
				classify = {
					errorPatterns = { "boot failed", "refused" },
					ignorePatterns = { "transport refused" },
					caseInsensitive = true,
				},
			}
			local captured = assert(outcome.record)
			check:expect(#captured.consoleErrorLines):toEqual(1)
			check:expect(captured.consoleErrorLines[1]):toEqual "BOOT FAILED at once"
		end)

		suite:case("refuses a screenshot that is the whole document window", function(check)
			local outcome = record {
				screenshot = pngBytes(1440, 900, 90 * 1024),
				windowBounds = { width = 1440, height = 900 },
			}
			assert(not outcome.ok, "expected refusal")
			check:expect(outcome.reason):toEqual "frame_not_viewport"
		end)

		suite:case("accepts a cropped screenshot against the same window bounds", function(check)
			local outcome = record { windowBounds = { width = 1440, height = 900 } }
			assert(outcome.ok, "expected a capture record")
		end)

		suite:case("refuses a bad target, a missing capture, and a malformed revision", function(check)
			check:expect(record({ target = "not a target" }).reason):toEqual "target_invalid"
			check:expect(record({ sourceSha = "short" }).reason):toEqual "sha_invalid"
			check
				:expect(WindowCapture.recordCapture({
					kind = KIND,
					target = "fixture-target",
					screenshot = pngBytes(844, 390, 90 * 1024),
					sourceSha = SHA,
					recordedAtUnix = 1000,
					sha256 = digest,
					classify = { errorPatterns = { "refused" } },
				}).reason)
				:toEqual "console_unreadable"
			check
				:expect(WindowCapture.recordCapture({
					kind = KIND,
					target = "fixture-target",
					console = "boot ok\n",
					sourceSha = SHA,
					recordedAtUnix = 1000,
					sha256 = digest,
					classify = { errorPatterns = { "refused" } },
				}).reason)
				:toEqual "screenshot_unreadable"
		end)

		suite:case("decodes only a capture record for this kind and target", function(check)
			local captured = assert((record {}).record)
			local decoded, problem = WindowCapture.decodeCapture(captured, KIND, "fixture-target")
			check:expect(problem):toEqual(nil)
			check:expect((decoded :: Lute.CaptureRecord).target):toEqual "fixture-target"

			local _, wrongKind = WindowCapture.decodeCapture(captured, "other.v1", "fixture-target")
			check:expect(wrongKind):toEqual "capture_record_invalid"

			local extra = (table.clone(captured) :: unknown) :: { [string]: unknown }
			extra.surprise = true
			local _, wrongShape = WindowCapture.decodeCapture(extra, KIND, "fixture-target")
			check:expect(wrongShape):toEqual "capture_record_invalid"
		end)

		suite:case("verifies a fresh capture record and names the revision range it covers", function(check)
			local captured = assert((record {}).record)
			local outcome = WindowCapture.checkCapture {
				record = captured,
				candidateSha = SHA,
				changeDeps = {
					isAncestor = function(): boolean
						return true
					end,
					changedPaths = function(): { string }
						return {}
					end,
				},
			}
			assert(outcome.ok, "expected verification")
			check
				:expect(((outcome.record :: unknown) :: { validForRange: { to: string } }).validForRange.to)
				:toEqual(SHA)
		end)

		suite:case("refuses a capture record whose console classified an error", function(check)
			local captured = assert((record { console = "attempt to call a nil value\n" }).record)
			local outcome = WindowCapture.checkCapture {
				record = captured,
				candidateSha = SHA,
				changeDeps = {
					isAncestor = function(): boolean
						return true
					end,
					changedPaths = function(): { string }
						return {}
					end,
				},
			}
			check:expect(outcome.reason):toEqual "console_red"
		end)

		suite:case("refuses a capture record whose subject changed since it was recorded", function(check)
			local captured = assert((record {}).record)
			local outcome = WindowCapture.checkCapture {
				record = captured,
				candidateSha = string.rep("2", 40),
				changeDeps = {
					isAncestor = function(): boolean
						return true
					end,
					changedPaths = function(): { string }
						return { "roblox/places/one" }
					end,
				},
			}
			check:expect(outcome.reason):toEqual "subject_changed_since_capture"
		end)
	end)
end
