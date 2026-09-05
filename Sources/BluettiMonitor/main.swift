import AppKit
import BluettiCore
import Darwin
import Foundation

if let flagIndex = CommandLine.arguments.firstIndex(of: "--localization-report") {
    let requestedLanguages: [String]
    if CommandLine.arguments.indices.contains(flagIndex + 1) {
        requestedLanguages = CommandLine.arguments[flagIndex + 1]
            .split(separator: ",")
            .map(String.init)
    } else {
        requestedLanguages = Locale.preferredLanguages
    }

    do {
        let data = try LocalizationReport(
            preferredLanguages: requestedLanguages
        ).jsonData()
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(EXIT_SUCCESS)
    } catch {
        FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
        exit(EXIT_FAILURE)
    }
}

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
