import AppKit
import Darwin
import Foundation

if let flagIndex = CommandLine.arguments.firstIndex(of: "--render-fixtures") {
    let outputPath: String
    if CommandLine.arguments.indices.contains(flagIndex + 1) {
        outputPath = CommandLine.arguments[flagIndex + 1]
    } else {
        outputPath = FileManager.default.currentDirectoryPath
            + "/.artifacts/ui-previews"
    }

    do {
        try PreviewRenderer.renderAll(
            to: URL(fileURLWithPath: outputPath, isDirectory: true)
        )
        exit(EXIT_SUCCESS)
    } catch {
        FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
        exit(EXIT_FAILURE)
    }
}

let application = NSApplication.shared
let applicationDelegate = AppDelegate()
application.delegate = applicationDelegate
application.run()
