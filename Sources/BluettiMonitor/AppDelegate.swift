import AppKit
import BluettiCore
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private static let firstRunCompletionKey = "didCompleteFirstRunSetup"
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var model: AppModel!
    private var session: BluettiDeviceSession!
    private var modelObserver: AnyCancellable?
    private var sessionStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let notificationService = NotificationService()
        let loginItemService = LoginItemService()
        model = AppModel(
            notifications: notificationService,
            loginItems: loginItemService,
            isFirstRunComplete: UserDefaults.standard.bool(
                forKey: Self.firstRunCompletionKey
            )
        )
        let central = BluetoothCentral()
        session = BluettiDeviceSession(central: central, model: model)
        model.reconnectAction = { [weak session] in session?.reconnect() }
        model.openBluetoothPrivacySettingsAction = { [weak central] in
            central?.openBluetoothPrivacySettings()
        }
        model.openBluetoothControlSettingsAction = { [weak central] in
            central?.openBluetoothControlSettings()
        }
        model.beginDeviceSelectionAction = { [weak session] in session?.beginDeviceSelection() }
        model.cancelDeviceSelectionAction = { [weak session] in session?.cancelDeviceSelection() }
        model.rescanDeviceSelectionAction = { [weak session] in session?.rescanDeviceSelection() }
        model.selectDeviceAction = { [weak session] id in session?.selectDevice(id) }
        model.startMonitoringAction = { [weak self] in self?.startSessionIfNeeded() }
        model.completeFirstRunAction = {
            UserDefaults.standard.set(true, forKey: Self.firstRunCompletionKey)
        }

        configureStatusItem()
        configurePopover()
        modelObserver = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateStatusItem()
                self?.updatePopoverAppearance()
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didChangeSystemLocale),
            name: NSLocale.currentLocaleDidChangeNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )

        if model.isFirstRunComplete {
            startSessionIfNeeded()
        }
        Task { [weak model] in await model?.refreshSystemHealth() }

        if !model.isFirstRunComplete {
            DispatchQueue.main.async { [weak self] in self?.showPopover() }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard model != nil else { return }
        Task { [weak model] in await model?.refreshSystemHealth() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    func popoverDidClose(_ notification: Notification) {
        model.setPopoverVisible(false)
    }

    @objc private func togglePopover() {
        popover.isShown ? popover.performClose(nil) : showPopover()
    }

    @objc private func didWake() {
        guard sessionStarted else { return }
        session.refreshImmediately()
    }

    @objc private func didChangeSystemLocale() {
        model.refreshSystemLanguage()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp])
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        updateStatusItem()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let hostingController = NSHostingController(
            rootView: PopoverView(model: model)
        )
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
        updatePopoverAppearance()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        Task { [weak model] in await model?.refreshSystemHealth() }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        model.setPopoverVisible(true)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func startSessionIfNeeded() {
        guard !sessionStarted else { return }
        sessionStarted = true
        session.start()
    }

    private func updateStatusItem() {
        guard let button = statusItem.button, model != nil else { return }
        let menuBar = MenuBarPresentation.make(.init(
            bluetooth: model.bluetooth,
            connection: model.connection,
            power: model.power,
            freshness: model.freshness
        ))
        let localizer = model.localizer
        button.image = MenuBarIconRenderer.image(
            for: menuBar.icon,
            accessibilityDescription: localizer.text("accessibility.bluettiState")
        )
        button.title = menuBar.title
        button.toolTip = localizer.format("menuBar.tooltip", model.presentation.title)
        button.setAccessibilityLabel(
            localizer.format("accessibility.menuBarStatus", model.presentation.title)
        )
    }

    private func updatePopoverAppearance() {
        let appearance = model.appearancePreference.appKitAppearance
        popover.appearance = appearance
        popover.contentViewController?.view.appearance = appearance
    }
}
