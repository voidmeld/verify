--!strict

local Verify = require "../src/core"

local fs = require "@std/fs"
local process = require "@std/process"
local Lute = require "../src/lute"
local Files = require "../src/lute/files"

local ROOT = ".lute/tmp/viewport-corners-spec"
local FIXTURE = [[
import Foundation
import CoreGraphics
import ImageIO
let mode = CommandLine.arguments[2]
let landscape = mode.hasPrefix("landscape")
let quantized = mode.hasPrefix("quantized")
let width = quantized ? 2800 : (landscape ? 1920 : 1000)
let height = quantized ? (mode == "quantized-clipped" ? 908 : 1000) : (landscape ? 890 : 900)
var pixels = [UInt8](repeating: 32, count: width * height * 4)
for i in 0..<(width * height) { pixels[i * 4 + 3] = 255 }
let bottomHeight = mode == "landscape-short" ? 8 : 9
let portraitPoints = [(100,100,5,5,255,0,255),(415,100,5,5,0,255,255),(100,788,5,4,255,255,0),(415,788,5,4,0,255,0)]
let landscapePoints = [(223,170,10,10,255,0,255),(1672,170,10,10,0,255,255),(223,834,10,bottomHeight,255,255,0),(1672,834,10,bottomHeight,0,255,0)]
let scale = 0.9965
let logicalPoints = [(0,0,255,0,255),(1274,0,0,255,255),(0,713,255,255,0),(1274,713,0,255,0)]
let quantizedPoints = logicalPoints.enumerated().map { i,p in
    let left = Int((17.6 + Double(p.0) * scale).rounded())
    let top = Int((194.1 + Double(p.1) * scale).rounded())
    let right = Int((17.6 + Double(p.0 + 6) * scale).rounded())
    let bottom = Int((194.1 + Double(p.1 + 6) * scale).rounded())
    let displacement = mode == "quantized-warped" && i >= 2 ? 1 : (mode == "quantized-skewed" && i == 3 ? 2 : 0)
    return (left,top+displacement,right-left,bottom-top,p.2,p.3,p.4)
}
let points = quantized ? quantizedPoints : (landscape ? landscapePoints : portraitPoints)
for (i,p) in points.enumerated() {
    if mode == "empty" || ((mode == "missing" || mode == "quantized-missing") && i == 3) { continue }
    let shifts = mode == "ambiguous" ? [0,500] : (mode == "quantized-ambiguous" ? [0,1400] : [0])
    for shift in shifts {
        for y in p.1..<min(height,p.1+p.3) { for x in (p.0+shift)..<(p.0+shift+p.2) {
            let at = (y * width + x) * 4
            pixels[at] = UInt8(p.4); pixels[at+1] = UInt8(p.5); pixels[at+2] = UInt8(p.6)
        } }
    }
}
let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
]]

local function options(path: string, logicalWidth: number?, logicalHeight: number?): Lute.ViewportCornerOptions
	return {
		packageRoot = ".",
		cacheDirectory = ROOT .. "/cache",
		imagePath = path,
		capabilities = { Lute.VIEWPORT_CORNER_CAPABILITY },
		logicalWidth = logicalWidth or 390,
		logicalHeight = logicalHeight or 844,
		markerSize = 6,
	}
end

return function(suite: Verify.Harness)
	suite:suite("native viewport corner capability", function()
		suite:case("does not touch missing paths without the declared capability", function(check)
			local request = options "missing.png"
			request.capabilities = {}
			check:expect(Lute.detectViewportCorners(request).status):toEqual "unsupported"
		end)

		suite:case("rejects malformed marker sizes before compilation and cleans failed compilation", function(check)
			if not fs.exists "/System/Library/CoreServices/SystemVersion.plist" then
				return
			end
			local owned = Files.claimDirectory(ROOT .. "/failure")
			Files.ensureDirectory(owned .. "/src/lute")
			fs.writeStringToFile(owned .. "/src/lute/viewport-corners.swift", "invalid swift source")
			fs.writeStringToFile(owned .. "/input.png", "fixture")
			local request = options(owned .. "/input.png")
			request.packageRoot = owned
			request.cacheDirectory = owned .. "/cache"
			local sizes: { any } = { 0, -1, 0.5, math.huge, math.nan, 390, "bad" }
			for _, size in sizes do
				(request :: any).markerSize = size
				check:expect(Lute.detectViewportCorners(request).reason):toEqual "corner_detector_marker_size_invalid"
				check:expect((fs.exists(request.cacheDirectory))):toEqual(false)
			end
			request.markerSize = 6
			local result = Lute.detectViewportCorners(request)
			check:expect(result.status):toEqual "held"
			check:expect((string.find(result.reason, "corner_detector_compile_failed:", 1, true))):toEqual(1)
			check:expect((#fs.listDirectory(request.cacheDirectory .. "/compile"))):toEqual(0)
		end)

		suite:case("detects one full rectangle and refuses missing or ambiguous corners", function(check)
			if not fs.exists "/System/Library/CoreServices/SystemVersion.plist" then
				check:expect(Lute.detectViewportCorners(options "missing.png").status):toEqual "unsupported"
				return
			end
			Files.ensureDirectory(ROOT)
			local source, binary = ROOT .. "/fixture.swift", ROOT .. "/fixture"
			fs.writeStringToFile(source, FIXTURE)
			local built = process.run { "/usr/bin/swiftc", "-O", "-o", binary, source }
			check:expect(built.ok):toEqual(true)
			for _, mode in { "valid", "missing", "ambiguous", "empty" } do
				local path = ROOT .. "/" .. mode .. ".png"
				check:expect(process.run({ binary, path, mode }).ok):toEqual(true)
				local result = Lute.detectViewportCorners(options(path))
				check:expect(result.status):toEqual(if mode == "valid" then "complete" else "held")
				if mode == "valid" then
					for key, value in { x = 100, y = 100, width = 320, height = 693 } do
						check:expect(result.data.captureRect[key]):toEqual(value)
					end
				end
				local request = options(path)
				request.inspect = true
				check:expect(Lute.detectViewportCorners(request).status):toEqual "complete"
			end
		end)

		suite:case("accepts raster-rounded landscape markers and refuses a shorter bottom edge", function(check)
			if not fs.exists "/System/Library/CoreServices/SystemVersion.plist" then
				return
			end
			Files.ensureDirectory(ROOT)
			local source, binary = ROOT .. "/landscape-fixture.swift", ROOT .. "/landscape-fixture"
			fs.writeStringToFile(source, FIXTURE)
			local built = process.run { "/usr/bin/swiftc", "-O", "-o", binary, source }
			check:expect(built.ok):toEqual(true)
			for _, mode in { "landscape", "landscape-short" } do
				local path = ROOT .. "/" .. mode .. ".png"
				check:expect(process.run({ binary, path, mode }).ok):toEqual(true)
				local result = Lute.detectViewportCorners(options(path, 844, 390))
				check:expect(result.status):toEqual(if mode == "landscape" then "complete" else "held")
				if mode == "landscape" then
					for key, value in { x = 223, y = 170, width = 1459, height = 674 } do
						check:expect(result.data.captureRect[key]):toEqual(value)
					end
					check:expect(result.data.markers.BL.height):toEqual(9)
					check:expect(result.data.markers.BR.height):toEqual(9)
				end
			end
		end)

		suite:case(
			"intersects per-axis raster quantization while refusing distorted or incomplete rectangles",
			function(check)
				if not fs.exists "/System/Library/CoreServices/SystemVersion.plist" then
					return
				end
				Files.ensureDirectory(ROOT)
				local source, binary = ROOT .. "/quantized-fixture.swift", ROOT .. "/quantized-fixture"
				fs.writeStringToFile(source, FIXTURE)
				check:expect(process.run({ "/usr/bin/swiftc", "-O", "-o", binary, source }).ok):toEqual(true)
				for _, mode in
					{
						"quantized",
						"quantized-warped",
						"quantized-skewed",
						"quantized-clipped",
						"quantized-missing",
						"quantized-ambiguous",
					}
				do
					local path = ROOT .. "/" .. mode .. ".png"
					check:expect(process.run({ binary, path, mode }).ok):toEqual(true)
					local result = Lute.detectViewportCorners(options(path, 1280, 719))
					check:expect(result.status):toEqual(if mode == "quantized" then "complete" else "held")
					if mode == "quantized" then
						for key, value in { x = 18, y = 194, width = 1275, height = 717 } do
							check:expect(result.data.captureRect[key]):toEqual(value)
						end
					elseif mode == "quantized-ambiguous" then
						check
							:expect(string.find(result.reason, "ambiguous calibration rectangles", 1, true) ~= nil)
							:toEqual(true)
					end
				end
			end
		)
	end)
end
