--!strict

local test = require "@std/test"

local Roblox = require "../src/roblox"

local HOST_PID = 4242

local REASONS: Roblox.CaptureReasons = {
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

local function window(overrides: { [string]: any }): Roblox.Window
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
	cropped: { { path: string, target: Roblox.ViewportTarget } },
	rectCropped: { { path: string, rect: Roblox.ViewportRect } },
}

local function deps(overrides: { [string]: any }): (Roblox.CaptureDeps, Recorder)
	local recorder: Recorder = { captured = {}, cropped = {}, rectCropped = {} }
	local bound: Roblox.CaptureDeps = {
		windowList = function(): Roblox.WindowList
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
		cropToViewport = function(_from: string, _to: string, target: Roblox.ViewportTarget): Roblox.CropOutcome
			table.insert(recorder.cropped, { path = _to, target = target })
			return overrides.cropOutcome
				or { ok = true, rect = { x = 10, y = 20, width = target.width, height = target.height } }
		end,
		cropToRect = function(_from: string, _to: string, rect: Roblox.ViewportRect): Roblox.CropOutcome
			table.insert(recorder.rectCropped, { path = _to, rect = rect })
			return overrides.rectCropOutcome or { ok = true, rect = rect }
		end,
		readFrame = function(_path: string): string?
			return overrides.file
		end,
	}
	return bound, recorder
end

local function capture(overrides: { [string]: any }, extra: { [string]: any }?): (Roblox.CaptureFrame, Recorder)
	local bound, recorder = deps(overrides)
	local options: Roblox.CaptureOptions = {
		pid = HOST_PID,
		outPath = "shots/witness.png",
		deps = bound,
		reasons = REASONS,
	}
	for key, value in (extra or {}) :: { [string]: any } do
		(options :: any)[key] = value
	end
	return Roblox.captureFrame(options), recorder
end

test.suite("explicit capture geometry", function(suite)
	suite:case("captures the selected document even when another is larger", function(assert)
		local outcome, recorder = capture(
			{ rows = { window { id = 7 }, window { id = 8, width = 2000 } }, file = pngBytes(1000, 600, 60000) },
			{ windowId = 7 }
		)
		assert.eq(outcome.ok, true)
		assert.eq(recorder.captured[1].id, 7)
	end)

	suite:case("does not substitute a different document after the selected window disappears", function(assert)
		local outcome, recorder = capture({ rows = { window { id = 8 } } }, { windowId = 7 })
		assert.eq(outcome.ok, false)
		assert.eq(#recorder.captured, 0)
	end)

	suite:case("compares Retina pixels against explicitly scaled window points", function(assert)
		assert.eq(Roblox.looksLikeWholeWindow(2880, 1800, 1440, 900, nil, 2), true)
		assert.eq(Roblox.looksLikeWholeWindow(1400, 800, 1440, 900, nil, 2), false)
		assert.eq(Roblox.looksLikeWholeWindow(1440, 900, 1440, 900), true)
		assert.eq(pcall(Roblox.looksLikeWholeWindow, 100, 100, 100, 100, nil, 0), false)
	end)
end)

test.suite("roblox witness host window capture", function(suite)
	suite:case("parses only tab-separated window rows and drops the rest", function(assert)
		local rows = Roblox.parseWindowRows "4242\t7\t0\t1440\t900\tEditor\nnoise line\n4242\t8\t3\t80\t20\tMenu\n"
		assert.eq(#rows, 2)
		assert.eq(rows[1].id, 7)
		assert.eq(rows[1].owner, "Editor")
		assert.eq(rows[2].layer, 3)
	end)

	suite:case("chooses the largest document-layer window and breaks ties on the lowest id", function(assert)
		local rows = {
			window { id = 9, width = 800, height = 600 },
			window { id = 3, width = 1440, height = 900 },
			window { id = 2, width = 1440, height = 900 },
			window { id = 1, width = 4000, height = 3000, layer = 25 },
		}
		local selection = Roblox.selectWindow(rows, HOST_PID, REASONS)
		assert.that(selection.ok, "expected a window")
		assert.eq((selection :: any).window.id, 2)
	end)

	suite:case("refuses when the pid owns windows but none is a document window", function(assert)
		local selection = Roblox.selectWindow({ window { layer = 25 } }, HOST_PID, REASONS)
		assert.eq((selection :: any).reason, "frame_no_window")
		assert.that(string.find((selection :: any).detail, "owns 1 on-screen window", 1, true) ~= nil, "detail counts")
	end)

	suite:case("refuses a pid the host does not own", function(assert)
		local outcome = capture { pids = { 1, 2 } }
		assert.eq((outcome :: any).reason, "frame_not_host")
	end)

	suite:case("saves the whole document window when neither viewport nor rect is given", function(assert)
		local outcome, recorder = capture { file = pngBytes(1440, 900, 90 * 1024) }
		assert.that(outcome.ok, "expected a frame")
		assert.eq((outcome :: any).width, 1440)
		assert.eq((outcome :: any).viewportRect, nil)
		assert.eq(#recorder.cropped, 0)
		assert.eq(recorder.captured[1].path, "shots/witness.png")
	end)

	suite:case("crops to an exact rect and never runs the aspect search", function(assert)
		local rect = { x = 324, y = 222, width = 1065, height = 500 }
		local outcome, recorder = capture({ file = pngBytes(1065, 500, 90 * 1024) }, { rect = rect })
		assert.that(outcome.ok, "expected a frame")
		assert.eq((outcome :: any).viewportRect.width, 1065)
		assert.eq(#recorder.cropped, 0)
		assert.eq(#recorder.rectCropped, 1)
		assert.eq(recorder.captured[1].path, "shots/witness.png.window.png")
	end)

	suite:case("prefers an explicit rect over a viewport target when both are given", function(assert)
		local _, recorder = capture({ file = pngBytes(1065, 500, 90 * 1024) }, {
			viewport = { width = 844, height = 390 },
			rect = { x = 0, y = 0, width = 1065, height = 500 },
		})
		assert.eq(#recorder.cropped, 0)
		assert.eq(#recorder.rectCropped, 1)
	end)

	suite:case("asks the host cropper for an aspect match when only a viewport is given", function(assert)
		local outcome, recorder = capture(
			{ file = pngBytes(844, 390, 90 * 1024) },
			{ viewport = { width = 844, height = 390 } }
		)
		assert.that(outcome.ok, "expected a frame")
		assert.eq(#recorder.cropped, 1)
		assert.eq(recorder.cropped[1].target.width, 844)
	end)

	suite:case("refuses a frame that is too thin, not a png, or missing", function(assert)
		assert.eq((capture { file = pngBytes(1440, 900, 1024) } :: any).reason, "frame_thin")
		assert.eq((capture { file = string.rep("x", 90 * 1024) } :: any).reason, "frame_not_png")
		assert.eq((capture {} :: any).reason, "frame_missing")
	end)

	suite:case("passes a cropper refusal through unchanged", function(assert)
		local outcome = capture({
			file = pngBytes(844, 390, 90 * 1024),
			rectCropOutcome = { ok = false, reason = "viewport_unresolved", detail = "cropper refused" },
		}, { rect = { x = 0, y = 0, width = 10, height = 10 } })
		assert.eq((outcome :: any).reason, "viewport_unresolved")
		assert.eq((outcome :: any).detail, "cropper refused")
	end)

	suite:case("reports the document window size the capture would have used", function(assert)
		local bound = deps { rows = { window { width = 1600, height = 1000 } } }
		local width, height, failure = Roblox.documentWindowSize(HOST_PID, bound, REASONS)
		assert.eq(width, 1600)
		assert.eq(height, 1000)
		assert.eq(failure, nil)
	end)

	suite:case("reads a pid only from a plain decimal string", function(assert)
		assert.eq(Roblox.parsePid "4242", 4242)
		assert.eq(Roblox.parsePid "-1", nil)
		assert.eq(Roblox.parsePid "42a", nil)
		assert.eq(Roblox.parsePid(nil), nil)
	end)
end)

test.suite("roblox witness host change freshness", function(suite)
	local function changeDeps(ancestor: boolean, changed: { string }): Roblox.ChangeDeps
		return {
			isAncestor = function(): boolean
				return ancestor
			end,
			changedPaths = function(): { string }
				return changed
			end,
		}
	end

	suite:case("accepts the identical revision without asking the host anything", function(assert)
		local asked = false
		local ok = Roblox.acceptsChange("a", "a", {
			isAncestor = function(): boolean
				asked = true
				return false
			end,
			changedPaths = function(): { string }
				return {}
			end,
		})
		assert.that(ok, "expected acceptance")
		assert.that(not asked, "expected no ancestry question")
	end)

	suite:case("refuses a recorded revision that is not an ancestor of the candidate", function(assert)
		local ok, reason = Roblox.acceptsChange("a", "b", changeDeps(false, {}))
		assert.that(not ok, "expected refusal")
		assert.eq(reason, "sha_not_ancestor")
	end)

	suite:case("refuses when a watched path changed between the two revisions", function(assert)
		local ok, reason, detail = Roblox.acceptsChange("a", "b", changeDeps(true, { "roblox/places/one" }))
		assert.that(not ok, "expected refusal")
		assert.eq(reason, "subject_changed_since_witness")
		assert.eq(detail, "roblox/places/one")
	end)

	suite:case("excludes exactly the paths the adopter supplies", function(assert)
		local args = Roblox.changedPathArgs("a", "b", { "docs", "tools" })
		assert.eq(args[#args - 1], ":(exclude)docs")
		assert.eq(args[#args], ":(exclude)tools")
	end)
end)

test.suite("roblox witness host checkpoint frames", function(suite)
	local function frame(overrides: { [string]: any }): { [string]: any }
		local row: { [string]: any } = {
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

	suite:case("returns frames in the adopter's checkpoint order, not the array's", function(assert)
		local ordered, failure = Roblox.checkpointFrames {
			frames = { frame { checkpoint = "arrival" }, frame { checkpoint = "boot" } },
			checkpoints = { "boot", "arrival" },
			framePath = framePath,
		}
		assert.eq(failure, nil)
		assert.eq((ordered :: any)[1].checkpoint, "boot")
		assert.eq((ordered :: any)[2].checkpoint, "arrival")
		assert.eq((ordered :: any)[1].windowWidth, nil)
	end)

	suite:case("refuses a missing checkpoint by name", function(assert)
		local _, failure = Roblox.checkpointFrames {
			frames = { frame { checkpoint = "boot" } },
			checkpoints = { "boot", "arrival" },
			framePath = framePath,
		}
		assert.eq(failure, "frame_missing: arrival")
	end)

	suite:case("refuses a frame saved anywhere but the derived path", function(assert)
		local _, failure = Roblox.checkpointFrames {
			frames = { frame { checkpoint = "boot", path = "elsewhere.png" } },
			checkpoints = { "boot" },
			framePath = framePath,
		}
		assert.eq(failure, "frame_missing: boot")
	end)

	suite:case("refuses a frame that is the whole window rather than a viewport", function(assert)
		local _, failure = Roblox.checkpointFrames {
			frames = { frame { checkpoint = "boot", width = 1440, height = 900 } },
			checkpoints = { "boot" },
			framePath = framePath,
		}
		assert.eq(failure, "frame_not_viewport: boot")
	end)

	suite:case("refuses duplicate checkpoint labels instead of selecting the last capture", function(assert)
		local _, failure = Roblox.checkpointFrames {
			frames = { frame { checkpoint = "boot" }, frame { checkpoint = "boot", sha256 = string.rep("b", 64) } },
			checkpoints = { "boot" },
			framePath = framePath,
		}
		assert.eq(failure, "frame_duplicate_checkpoint: boot")
	end)

	suite:case("refuses reused image bytes when distinct observations are required", function(assert)
		local _, failure = Roblox.checkpointFrames {
			frames = { frame { checkpoint = "boot" }, frame { checkpoint = "arrival" } },
			checkpoints = { "boot", "arrival" },
			framePath = framePath,
			requireDistinctFrames = true,
		}
		assert.eq(failure, "frame_reused: arrival duplicates boot")
	end)

	suite:case("accepts distinct observations under the strict capture policy", function(assert)
		local frames, failure = Roblox.checkpointFrames {
			frames = { frame { checkpoint = "boot" }, frame { checkpoint = "arrival", sha256 = string.rep("b", 64) } },
			checkpoints = { "boot", "arrival" },
			framePath = framePath,
			requireDistinctFrames = true,
		}
		assert.eq(failure, nil)
		assert.eq(#(frames :: any), 2)
	end)

	suite:case("refuses observations carrying no frame table at all", function(assert)
		local _, failure = Roblox.checkpointFrames { frames = nil, checkpoints = { "boot" }, framePath = framePath }
		assert.eq(failure, "frame_missing: observation carries no frames")
	end)
end)

test.suite("roblox witness host receipts", function(suite)
	local SHA = string.rep("1", 40)
	local CONTRACT = "host.witness.v1"

	local function digest(value: string): string
		return string.sub(string.rep(tostring(#value), 64), 1, 64)
	end

	local function record(overrides: { [string]: any }): Roblox.WitnessOutcome
		local options: Roblox.RecordReceiptOptions = {
			contract = CONTRACT,
			target = "fixture-target",
			console = "boot ok\n",
			screenshot = pngBytes(844, 390, 90 * 1024),
			sourceSha = SHA,
			recordedAtUnix = 1000,
			sha256 = digest,
		}
		for key, value in overrides do
			(options :: any)[key] = value
		end
		return Roblox.recordReceipt(options)
	end

	suite:case("rejects a whole Retina window using the host supplied pixel scale", function(assert)
		local outcome = record {
			screenshot = pngBytes(2880, 1800, 90000),
			windowBounds = { width = 1440, height = 900, pixelScale = 2 },
		}
		assert.eq(outcome.ok, false)
		assert.eq(outcome.reason, "frame_not_viewport")
	end)

	suite:case("binds console classification, hashes and the clock the caller handed in", function(assert)
		local outcome = record { console = "boot ok\nattempt to index nil\n" }
		assert.that(outcome.ok, "expected a receipt")
		local receipt = outcome.receipt :: any
		assert.eq(receipt.contract, CONTRACT)
		assert.eq(receipt.recordedAtUnix, 1000)
		assert.eq(#receipt.consoleErrorLines, 1)
		assert.eq(receipt.consoleErrorLines[1], "attempt to index nil")
	end)

	suite:case("classifies through the adopter's own patterns and exclusions", function(assert)
		local outcome = record {
			console = "COMPOSITION FAILED at boot\nborder transport refused\n",
			classify = {
				errorPatterns = { "composition failed", "refused" },
				ignorePatterns = { "border transport refused" },
				caseInsensitive = true,
			},
		}
		local receipt = outcome.receipt :: any
		assert.eq(#receipt.consoleErrorLines, 1)
		assert.eq(receipt.consoleErrorLines[1], "COMPOSITION FAILED at boot")
	end)

	suite:case("refuses a screenshot that is the whole document window", function(assert)
		local outcome = record {
			screenshot = pngBytes(1440, 900, 90 * 1024),
			windowBounds = { width = 1440, height = 900 },
		}
		assert.that(not outcome.ok, "expected refusal")
		assert.eq(outcome.reason, "frame_not_viewport")
	end)

	suite:case("accepts a cropped screenshot against the same window bounds", function(assert)
		local outcome = record { windowBounds = { width = 1440, height = 900 } }
		assert.that(outcome.ok, "expected a receipt")
	end)

	suite:case("refuses a bad target, a missing capture, and a malformed revision", function(assert)
		assert.eq(record({ target = "not a target" }).reason, "target_invalid")
		assert.eq(record({ sourceSha = "short" }).reason, "sha_invalid")
		assert.eq(
			Roblox.recordReceipt({
				contract = CONTRACT,
				target = "fixture-target",
				screenshot = pngBytes(844, 390, 90 * 1024),
				sourceSha = SHA,
				recordedAtUnix = 1000,
				sha256 = digest,
			}).reason,
			"console_unreadable"
		)
		assert.eq(
			Roblox.recordReceipt({
				contract = CONTRACT,
				target = "fixture-target",
				console = "boot ok\n",
				sourceSha = SHA,
				recordedAtUnix = 1000,
				sha256 = digest,
			}).reason,
			"screenshot_unreadable"
		)
	end)

	suite:case("decodes only a receipt for this contract and target", function(assert)
		local receipt = (record {}).receipt :: any
		local decoded, problem = Roblox.decodeReceipt(receipt, CONTRACT, "fixture-target")
		assert.eq(problem, nil)
		assert.eq((decoded :: any).target, "fixture-target")

		local _, wrongContract = Roblox.decodeReceipt(receipt, "other.v1", "fixture-target")
		assert.eq(wrongContract, "receipt_invalid")

		local extra = table.clone(receipt)
		extra.surprise = true
		local _, wrongShape = Roblox.decodeReceipt(extra, CONTRACT, "fixture-target")
		assert.eq(wrongShape, "receipt_invalid")
	end)

	suite:case("verifies a fresh receipt and names the revision range it covers", function(assert)
		local receipt = (record {}).receipt :: any
		local outcome = Roblox.checkReceipt {
			receipt = receipt,
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
		assert.that(outcome.ok, "expected verification")
		assert.eq((outcome.receipt :: any).validForRange.to, SHA)
	end)

	suite:case("refuses a receipt whose console classified an error", function(assert)
		local receipt = (record { console = "attempt to call a nil value\n" }).receipt :: any
		local outcome = Roblox.checkReceipt {
			receipt = receipt,
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
		assert.eq(outcome.reason, "console_red")
	end)

	suite:case("refuses a receipt whose subject changed since it was recorded", function(assert)
		local receipt = (record {}).receipt :: any
		local outcome = Roblox.checkReceipt {
			receipt = receipt,
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
		assert.eq(outcome.reason, "subject_changed_since_witness")
	end)
end)
