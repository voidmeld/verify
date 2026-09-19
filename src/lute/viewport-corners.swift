import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct Box: Codable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    var right: Int { x + width }
    var bottom: Int { y + height }
}
struct Detection: Codable {
    let originalWidth: Int
    let originalHeight: Int
    let logicalWidth: Int
    let logicalHeight: Int
    let logicalMarkerSize: Int
    let markers: [String: Box]
    let captureRect: Box
    let scaleX: Double
    let scaleY: Double
}
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
let supplied = Array(CommandLine.arguments.dropFirst())
let inspect = supplied.count == 2 && supplied[1] == "--inspect"
let args = inspect ? [supplied[0], "2", "2", "1"] : supplied
guard args.count == 4 || (args.count == 6 && args[4] == "--out"),
      let logicalWidth = Int(args[1]), let logicalHeight = Int(args[2]),
      let markerSize = Int(args[3]), markerSize > 0,
      logicalWidth > markerSize, logicalHeight > markerSize else {
    fail("usage: detector <image.png> <logicalWidth> <logicalHeight> <logicalMarkerSize> [--out <crop.png>]")
}
guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[0]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("cannot decode image") }
let width = image.width
let height = image.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let decoded = pixels.withUnsafeMutableBytes { bytes -> Bool in
    guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return true
}
guard decoded else { fail("cannot decode pixels") }
func colorAt(_ index: Int) -> Int {
    let offset = index * 4
    let r = pixels[offset], g = pixels[offset + 1], b = pixels[offset + 2]
    guard pixels[offset + 3] >= 250 else { return -1 }
    if r >= 245 && g <= 10 && b >= 245 { return 0 }
    if r <= 10 && g >= 245 && b >= 245 { return 1 }
    if r >= 245 && g >= 245 && b <= 10 { return 2 }
    if r <= 10 && g >= 245 && b <= 10 { return 3 }
    return -1
}
var visited = [Bool](repeating: false, count: width * height)
var components = [[Box]](repeating: [], count: 4)
for seed in 0..<(width * height) {
    if visited[seed] { continue }
    let color = colorAt(seed)
    if color < 0 { continue }
    var queue = [seed]
    visited[seed] = true
    var head = 0
    var minX = seed % width, maxX = minX, minY = seed / width, maxY = minY
    while head < queue.count {
        let index = queue[head]
        head += 1
        let x = index % width, y = index / width
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
        var neighbors = [Int]()
        if x > 0 { neighbors.append(index - 1) }
        if x + 1 < width { neighbors.append(index + 1) }
        if y > 0 { neighbors.append(index - width) }
        if y + 1 < height { neighbors.append(index + width) }
        for neighbor in neighbors where !visited[neighbor] && colorAt(neighbor) == color {
            visited[neighbor] = true
            queue.append(neighbor)
        }
    }
    let box = Box(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    if inspect || (abs(box.width - box.height) <= 1 && queue.count == box.width * box.height) {
        components[color].append(box)
    }
}
if inspect {
    let payload: [String: Any] = ["originalWidth": width, "originalHeight": height,
        "components": Dictionary(uniqueKeysWithValues: zip(["TL", "TR", "BL", "BR"], components).map { name, boxes in
            (name, boxes.map { ["x": $0.x, "y": $0.y, "width": $0.width, "height": $0.height] }) })]
    guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { fail("cannot encode inspection") }
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}
guard components.allSatisfy({ !$0.isEmpty }) else { fail("missing calibration marker") }
var matches = [Detection]()
for tl in components[0] {
    for tr in components[1] where tr.x > tl.right && abs(tr.y - tl.y) <= 1 {
        for bl in components[2] where bl.y > tl.bottom && abs(bl.x - tl.x) <= 1 {
            for br in components[3] where abs(br.x - tr.x) <= 1 && abs(br.y - bl.y) <= 1 {
                let scaleX = Double(tr.x - tl.x) / Double(logicalWidth - markerSize)
                let scaleY = Double(bl.y - tl.y) / Double(logicalHeight - markerSize)
                let horizontalQuantization = 1 / Double(logicalWidth - markerSize)
                let verticalQuantization = 1 / Double(logicalHeight - markerSize)
                let minimumScale = max(scaleX - horizontalQuantization, scaleY - verticalQuantization)
                let maximumScale = min(scaleX + horizontalQuantization, scaleY + verticalQuantization)
                guard minimumScale > 0 && minimumScale <= maximumScale else { continue }
                let cropWidth = Int((Double(logicalWidth) * scaleX).rounded())
                let cropHeight = Int((Double(logicalHeight) * scaleY).rounded())
                let expectedMarkerWidth = Int((Double(markerSize) * scaleX).rounded())
                let expectedMarkerHeight = Int((Double(markerSize) * scaleY).rounded())
                let boxes = [tl, tr, bl, br]
                guard boxes.allSatisfy({ abs($0.width - expectedMarkerWidth) <= 1 && abs($0.height - expectedMarkerHeight) <= 1 }),
                      abs(tl.width - tr.width) <= 1, abs(tl.width - bl.width) <= 1, abs(tl.width - br.width) <= 1,
                      abs(tl.height - tr.height) <= 1, abs(tl.height - bl.height) <= 1, abs(tl.height - br.height) <= 1,
                      abs(tl.x + cropWidth - tr.right) <= 1, abs(tl.x + cropWidth - br.right) <= 1,
                      abs(tl.y + cropHeight - bl.bottom) <= 1, abs(tl.y + cropHeight - br.bottom) <= 1,
                      tl.x + cropWidth <= width, tl.y + cropHeight <= height else { continue }
                matches.append(Detection(originalWidth: width, originalHeight: height, logicalWidth: logicalWidth,
                                         logicalHeight: logicalHeight, logicalMarkerSize: markerSize,
                                         markers: ["TL": tl, "TR": tr, "BL": bl, "BR": br],
                                         captureRect: Box(x: tl.x, y: tl.y, width: cropWidth, height: cropHeight),
                                         scaleX: scaleX, scaleY: scaleY))
            }
        }
    }
}
guard matches.count == 1 else { fail(matches.isEmpty ? "calibration geometry is inconsistent" : "ambiguous calibration rectangles") }
let detection = matches[0]
if args.count == 6 {
    let rect = detection.captureRect
    guard let cropped = image.cropping(to: CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)),
          let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[5]) as CFURL, UTType.png.identifier as CFString, 1, nil) else { fail("cannot create crop") }
    CGImageDestinationAddImage(destination, cropped, nil)
    guard CGImageDestinationFinalize(destination) else { fail("cannot save crop") }
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
do {
    let encoded = try encoder.encode(detection)
    print(String(decoding: encoded, as: UTF8.self))
} catch { fail("cannot encode detection") }
