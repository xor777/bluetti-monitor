#!/usr/bin/swift

import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("usage: make-icns.swift ICONSET OUTPUT.icns\n", stderr)
    exit(2)
}

let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let entries = [
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_128x128@2x.png"),
    ("ic09", "icon_256x256@2x.png"),
    ("ic10", "icon_512x512@2x.png"),
    ("ic11", "icon_16x16@2x.png"),
    ("ic12", "icon_32x32@2x.png"),
    ("ic13", "icon_128x128@2x.png"),
    ("ic14", "icon_256x256@2x.png"),
]

func bigEndianData(_ value: UInt32) -> Data {
    var value = value.bigEndian
    return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
}

let chunks = try entries.map { type, filename in
    (type, try Data(contentsOf: iconset.appendingPathComponent(filename)))
}

var tableOfContents = Data()
for (type, png) in chunks {
    tableOfContents.append(Data(type.utf8))
    tableOfContents.append(bigEndianData(UInt32(png.count + 8)))
}

var body = Data("TOC ".utf8)
body.append(bigEndianData(UInt32(tableOfContents.count + 8)))
body.append(tableOfContents)

for (type, png) in chunks {
    body.append(Data(type.utf8))
    body.append(bigEndianData(UInt32(png.count + 8)))
    body.append(png)
}

var icns = Data("icns".utf8)
icns.append(bigEndianData(UInt32(body.count + 8)))
icns.append(body)
try icns.write(to: output, options: .atomic)
