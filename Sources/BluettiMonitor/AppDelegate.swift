import AppKit
import BluettiCore
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var model: AppModel!
    private var session: BluettiDeviceSession!
    private var modelObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let notificationService = NotificationService()
        model = AppModel(notifications: notificationService)
        let central = BluetoothCentral()
        session = BluettiDeviceSession(central: central, model: model)
        model.reconnectAction = { [weak session] in session?.reconnect() }
        model.openBluetoothSettingsAction = { [weak central] in central?.openBluetoothSettings() }

        configureStatusItem()
        configurePopover()
        modelObserver = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatusItem() }
        }

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

        session.start()
        Task { await notificationService.prepare() }

        if !UserDefaults.standard.bool(forKey: "didShowFirstRunPopover") {
            UserDefaults.standard.set(true, forKey: "didShowFirstRunPopover")
            DispatchQueue.main.async { [weak self] in self?.showPopover() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func popoverDidClose(_ notification: Notification) {
        model.setPopoverVisible(false)
    }

    @objc private func togglePopover() {
        popover.isShown ? popover.performClose(nil) : showPopover()
    }

    @objc private func didWake() {
        session.refreshImmediately()
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
        popover.contentSize = NSSize(width: 440, height: 330)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(model: model)
        )
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        model.setPopoverVisible(true)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateStatusItem() {
        guard let button = statusItem.button, model != nil else { return }
        let menuBar = MenuBarPresentation.make(.init(
            bluetooth: model.bluetooth,
            connection: model.connection,
            power: model.power,
            freshness: model.freshness
        ))
        button.image = MenuBarIconRenderer.image(for: menuBar.icon)
        button.title = menuBar.title
        button.toolTip = "Bluetti Monitor · \(model.presentation.title)"
        button.setAccessibilityLabel("Bluetti Monitor, \(model.presentation.title)")
    }
}
