import AppKit
import BluettiCore
import Foundation
import SwiftUI

@MainActor
enum PreviewRenderer {
    static func renderAll(to outputDirectory: URL) throws {
        _ = NSApplication.shared
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        var manifest: [String] = []
        for fixture in PreviewFixture.all {
            for theme in PreviewTheme.allCases {
                let filename = "\(fixture.name)-\(theme.rawValue).png"
                let destination = outputDirectory.appendingPathComponent(filename)
                let size = try render(fixture.state, theme: theme, to: destination)
                manifest.append("\(filename)\t\(Int(size.width))x\(Int(size.height)) points")
                print(destination.path)
            }
        }

        try verifyAdaptiveHostingSize()

        let manifestURL = outputDirectory.appendingPathComponent("manifest.txt")
        try (manifest.joined(separator: "\n") + "\n").write(
            to: manifestURL,
            atomically: true,
            encoding: .utf8
        )
        print("Rendered \(manifest.count) SwiftUI fixtures in \(outputDirectory.path)")
    }

    private static func render(
        _ state: PopoverViewState,
        theme: PreviewTheme,
        to destination: URL
    ) throws -> NSSize {
        let background = theme == .dark
            ? Color(nsColor: NSColor(calibratedWhite: 0.105, alpha: 1))
            : Color(nsColor: NSColor(calibratedWhite: 0.965, alpha: 1))
        let content = PopoverContentView(state: state, actions: .none)
            .environment(\.colorScheme, theme.colorScheme)
            .environment(\.locale, Locale(identifier: "ru_RU"))
            .background(background)
        let hostingController = NSHostingController(rootView: AnyView(content))
        hostingController.sizingOptions = [.preferredContentSize]
        let hostingView = hostingController.view
        let appearance = NSAppearance(
            named: theme == .dark ? .darkAqua : .aqua
        )
        hostingView.appearance = appearance
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: MonitorStyle.width,
            height: 1
        )
        hostingView.layoutSubtreeIfNeeded()

        let fittingSize = hostingController.sizeThatFits(
            in: NSSize(width: MonitorStyle.width, height: 2_000)
        )
        let size = NSSize(width: MonitorStyle.width, height: ceil(fittingSize.height))
        hostingView.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance
        window.backgroundColor = theme == .dark
            ? NSColor(calibratedWhite: 0.105, alpha: 1)
            : NSColor(calibratedWhite: 0.965, alpha: 1)
        window.isOpaque = true
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.displayIfNeeded()
        hostingView.displayIfNeeded()

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw PreviewRendererError.couldNotEncode(destination.lastPathComponent)
        }
        bitmap.size = size
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        window.contentView = nil
        window.close()

        guard let png = bitmap.representation(
            using: NSBitmapImageRep.FileType.png,
            properties: [:]
        ) else {
            throw PreviewRendererError.couldNotEncode(destination.lastPathComponent)
        }
        try png.write(to: destination, options: Data.WritingOptions.atomic)
        return size
    }

    private static func verifyAdaptiveHostingSize() throws {
        guard let normal = PreviewFixture.all.first(where: { $0.name == "healthy" }),
              let settings = PreviewFixture.all.first(where: { $0.name == "settings" })
        else {
            throw PreviewRendererError.invalidAdaptiveSize
        }

        let controller = NSHostingController(
            rootView: AnyView(previewContent(normal.state, theme: .light))
        )
        controller.sizingOptions = [.preferredContentSize]
        let normalSize = measuredSize(of: controller)
        controller.rootView = AnyView(previewContent(settings.state, theme: .light))
        let settingsSize = measuredSize(of: controller)

        guard normalSize.height > 0,
              settingsSize.height > 0,
              abs(normalSize.height - settingsSize.height) > 10
        else {
            throw PreviewRendererError.invalidAdaptiveSize
        }
        print(
            "Adaptive hosting size: normal \(Int(normalSize.width))x\(Int(normalSize.height)), "
                + "settings \(Int(settingsSize.width))x\(Int(settingsSize.height)) points"
        )
    }

    private static func measuredSize(
        of controller: NSHostingController<AnyView>
    ) -> NSSize {
        let size = controller.sizeThatFits(
            in: NSSize(width: MonitorStyle.width, height: 2_000)
        )
        controller.view.frame = NSRect(origin: .zero, size: size)
        controller.view.layoutSubtreeIfNeeded()
        return controller.preferredContentSize.height > 0
            ? controller.preferredContentSize
            : size
    }

    private static func previewContent(
        _ state: PopoverViewState,
        theme: PreviewTheme
    ) -> some View {
        PopoverContentView(state: state, actions: .none)
            .environment(\.colorScheme, theme.colorScheme)
            .environment(\.locale, Locale(identifier: "ru_RU"))
    }
}

private enum PreviewTheme: String, CaseIterable {
    case light
    case dark

    var colorScheme: ColorScheme {
        self == .light ? .light : .dark
    }
}

private struct PreviewFixture {
    let name: String
    let state: PopoverViewState

    static let all: [PreviewFixture] = {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let current = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let office = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let studio = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        let choices = [
            PopoverStationChoice(
                id: current,
                name: "Premium 100 V2",
                identity: "HOME-41",
                isCurrent: true
            ),
            PopoverStationChoice(
                id: office,
                name: "Premium 100 V2",
                identity: "OFFICE-2A",
                isCurrent: false
            ),
            PopoverStationChoice(
                id: studio,
                name: "Premium 100 V2",
                identity: "3333…3333",
                isCurrent: false
            ),
        ]

        func make(
            screen: PopoverScreen = .normal,
            bluetooth: BluetoothAvailability = .poweredOn,
            connection: DeviceConnectionState = .connected,
            power: ExternalPowerState = .online,
            freshness: DataFreshness = .fresh,
            snapshot: DeviceSnapshot = DeviceSnapshot(
                model: "PR100V2",
                batteryPercent: 78,
                acInputVoltage: 230,
                acInputPower: 186,
                acOutputPower: 132
            ),
            powerConfirmed: Bool = true,
            scanningFor: TimeInterval = 0,
            batteryState: LowBatteryVisualState = .normal,
            monitoringDetail: String? = nil,
            monitoringRecovery: MonitoringRecoveryAction? = nil,
            notificationHealth: NotificationHealth = .available,
            notificationResult: NotificationActionResult? = nil,
            lastUpdateAge: TimeInterval? = 1,
            outageStartedAt: Date? = nil,
            selectedID: UUID? = current,
            stationCandidates: [PopoverStationChoice]? = nil,
            selectionMode: StationSelectionMode = .selectedOnly,
            canCancelSelection: Bool = false,
            loginStatus: LoginItemStatus = .disabled,
            loginError: String? = nil,
            launchAtLogin: Bool = false
        ) -> PopoverViewState {
            let presentation = StatusPresentation.make(.init(
                bluetooth: bluetooth,
                connection: connection,
                power: power,
                freshness: freshness,
                powerConfirmedInCurrentSession: powerConfirmed,
                scanningFor: scanningFor,
                inputPower: snapshot.acInputPower,
                outputPower: snapshot.acOutputPower
            ))
            return PopoverViewState(
                screen: screen,
                deviceName: "Premium 100 V2",
                deviceIdentity: selectedID == nil ? nil : "HOME-41",
                bluetooth: bluetooth,
                connection: connection,
                power: power,
                freshness: freshness,
                snapshot: snapshot,
                presentation: presentation,
                batteryVisualState: batteryState,
                monitoringDetail: monitoringDetail,
                monitoringRecovery: monitoringRecovery,
                notificationReadiness: .make(notificationHealth),
                notificationActionResult: notificationResult,
                lastUpdate: lastUpdateAge.map { now.addingTimeInterval(-$0) },
                outageStartedAt: outageStartedAt,
                now: now,
                isVisible: true,
                animationsEnabled: false,
                selectedID: selectedID,
                stationCandidates: stationCandidates ?? Array(choices.prefix(1)),
                selectionMode: selectionMode,
                canCancelDeviceSelection: canCancelSelection,
                loginItemStatus: loginStatus,
                loginItemError: loginError,
                launchAtLogin: launchAtLogin
            )
        }

        return [
            PreviewFixture(name: "healthy", state: make()),
            PreviewFixture(
                name: "backup",
                state: make(
                    power: .offline,
                    snapshot: DeviceSnapshot(
                        model: "PR100V2",
                        batteryPercent: 63,
                        acInputVoltage: 0,
                        acInputPower: 0,
                        acOutputPower: 128
                    ),
                    outageStartedAt: now.addingTimeInterval(-9 * 60)
                )
            ),
            PreviewFixture(
                name: "low-battery",
                state: make(
                    power: .online,
                    snapshot: DeviceSnapshot(
                        model: "PR100V2",
                        batteryPercent: 16,
                        acInputVoltage: 230,
                        acInputPower: 164,
                        acOutputPower: 121
                    ),
                    batteryState: .normal
                )
            ),
            PreviewFixture(
                name: "stale",
                state: make(
                    freshness: .stale,
                    snapshot: DeviceSnapshot(
                        model: "PR100V2",
                        batteryPercent: 54,
                        acInputVoltage: 230,
                        acInputPower: 176,
                        acOutputPower: 129
                    ),
                    batteryState: .unavailable,
                    lastUpdateAge: 18
                )
            ),
            PreviewFixture(
                name: "lost",
                state: make(
                    connection: .disconnected,
                    freshness: .lost,
                    snapshot: DeviceSnapshot(
                        model: "PR100V2",
                        batteryPercent: 49,
                        acInputVoltage: 0,
                        acInputPower: 0,
                        acOutputPower: 118
                    ),
                    powerConfirmed: false,
                    batteryState: .unavailable,
                    monitoringDetail: "Проверьте, не подключено ли приложение BLUETTI на телефоне",
                    monitoringRecovery: .reconnect,
                    lastUpdateAge: 125
                )
            ),
            PreviewFixture(
                name: "connected-partial",
                state: make(
                    power: .online,
                    snapshot: DeviceSnapshot(model: "PR100V2", acInputVoltage: 230),
                    powerConfirmed: true,
                    batteryState: .unavailable
                )
            ),
            PreviewFixture(
                name: "discovery-empty",
                state: make(
                    screen: .chooser,
                    connection: .scanning,
                    power: .unknown,
                    freshness: .lost,
                    snapshot: DeviceSnapshot(),
                    powerConfirmed: false,
                    scanningFor: 12,
                    batteryState: .unavailable,
                    selectedID: nil,
                    stationCandidates: [],
                    selectionMode: .choosing
                )
            ),
            PreviewFixture(
                name: "discovery-multiple",
                state: make(
                    screen: .chooser,
                    stationCandidates: choices,
                    selectionMode: .choosing,
                    canCancelSelection: true
                )
            ),
            PreviewFixture(
                name: "bluetooth-denied",
                state: make(
                    bluetooth: .unauthorized,
                    connection: .disconnected,
                    freshness: .lost,
                    snapshot: DeviceSnapshot(),
                    powerConfirmed: false,
                    batteryState: .unavailable,
                    monitoringRecovery: .openBluetoothSettings,
                    notificationHealth: .denied,
                    lastUpdateAge: nil
                )
            ),
            PreviewFixture(
                name: "bluetooth-off",
                state: make(
                    bluetooth: .poweredOff,
                    connection: .disconnected,
                    freshness: .lost,
                    snapshot: DeviceSnapshot(),
                    powerConfirmed: false,
                    batteryState: .unavailable,
                    monitoringRecovery: .openBluetoothSettings,
                    lastUpdateAge: nil
                )
            ),
            PreviewFixture(
                name: "notifications-denied",
                state: make(notificationHealth: .denied)
            ),
            PreviewFixture(
                name: "first-run",
                state: make(
                    screen: .setup,
                    bluetooth: .unknown,
                    connection: .disconnected,
                    power: .unknown,
                    freshness: .lost,
                    snapshot: DeviceSnapshot(),
                    powerConfirmed: false,
                    batteryState: .unavailable,
                    notificationHealth: .notDetermined,
                    lastUpdateAge: nil,
                    selectedID: nil,
                    stationCandidates: [],
                    selectionMode: .initialDiscovery
                )
            ),
            PreviewFixture(
                name: "first-run-chooser",
                state: make(
                    screen: .setup,
                    connection: .scanning,
                    power: .unknown,
                    freshness: .lost,
                    snapshot: DeviceSnapshot(),
                    powerConfirmed: false,
                    batteryState: .unavailable,
                    notificationHealth: .notDetermined,
                    lastUpdateAge: nil,
                    selectedID: nil,
                    stationCandidates: Array(choices.dropFirst()),
                    selectionMode: .choosing
                )
            ),
            PreviewFixture(
                name: "settings",
                state: make(
                    screen: .settings,
                    notificationResult: .failure(
                        "Не удалось запланировать уведомление: служба временно недоступна"
                    ),
                    loginStatus: .requiresApproval,
                    loginError: "Подтвердите Bluetti Monitor в настройках объектов входа",
                    launchAtLogin: true
                )
            ),
        ]
    }()
}

private enum PreviewRendererError: LocalizedError {
    case couldNotEncode(String)
    case invalidAdaptiveSize

    var errorDescription: String? {
        switch self {
        case let .couldNotEncode(filename):
            "Не удалось отрисовать \(filename)"
        case .invalidAdaptiveSize:
            "Высота SwiftUI popover не обновилась при смене экрана"
        }
    }
}
