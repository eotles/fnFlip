//
//  AppDelegate.swift
//  fnFlip
//
//  Copyright (c) 2025 Erkin Ötleş
//  Licensed under: MIT + Commons Clause (see LICENSE in repo root)
//  SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0
//

import Carbon.HIToolbox
import Cocoa
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    private let toggler = FnKeyToggler()
    private let icons = StatusIconController()
    private var isWorking = false

    /// Cached state so we never hit preferences on the main thread.
    /// nil means unknown. We show a gentle spinner until the first read completes.
    private var enabledState: Bool? {
        didSet {
            refreshVisualState()
            refreshButtonTooltip()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure only one copy runs
        if handOffToExistingInstanceIfAny() {
            NSApp.terminate(nil)
            return
        }

        // clockwise spin for the timer based icon
        icons.style.spinsPerSecond = -abs(icons.style.spinsPerSecond)

        _ = LaunchAtLogin.repairIfNeeded()
        LaunchAtLogin.enableByDefaultIfUnset()

        setupStatusItem()
        requestNotificationAuth()
        registerGlobalHotKey() // ⌘⌥F

        // Non-blocking initial read
        enabledState = nil
        toggler.readAsync { [weak self] value in
            self?.enabledState = value
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyConfig.unregister()
    }

    /// Returns true if another instance is already running; in that case it activates it.
    private func handOffToExistingInstanceIfAny() -> Bool {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let myBundleID = Bundle.main.bundleIdentifier

        let others = NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == myBundleID && $0.processIdentifier != myPID }

        guard let existing = others.first else { return false }
        _ = existing.activate(options: [.activateIgnoringOtherApps])
        return true
    }

    // MARK: Menu bar
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button { btn.imagePosition = .imageOnly }

        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        if let btn = statusItem.button {
            icons.apply(to: btn, state: .workingFromOff)
        }
        refreshButtonTooltip()
    }

    private func refreshButtonTooltip() {
        let shortcut = HotkeyConfig.displayString
        if let enabled = enabledState {
            statusItem.button?.toolTip = enabled
                ? "FnFlip: Standard F1, F2, etc. (click to switch) • Shortcut: \(shortcut)"
                : "FnFlip: Hardware Keys (click to switch) • Shortcut: \(shortcut)"
        } else {
            statusItem.button?.toolTip = "FnFlip: reading current state… • Shortcut: \(shortcut)"
        }
    }

    private func refreshVisualState() {
        guard let btn = statusItem.button else { return }
        let state: IconState
        switch enabledState {
        case .some(true):  state = .on
        case .some(false): state = .off
        case .none:        state = .workingFromOff
        }
        icons.apply(to: btn, state: state)
    }

    // MARK: Button clicks
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            toggleAction()
            return
        }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            let isOn = enabledState ?? false
            let menu = StatusMenuBuilder.build(
                isEnabled: isOn,
                isLaunchEnabled: LaunchAtLogin.isEnabled,
                toggleAction: #selector(toggleAction),
                launchAtLoginAction: #selector(toggleLaunchAtLogin(_:)),
                aboutAction: #selector(showAbout),
                quitAction: #selector(quit),
                target: self
            )
            StatusMenuBuilder.refresh(menu,
                                      isEnabled: isOn,
                                      isLaunchEnabled: LaunchAtLogin.isEnabled)

            if let btn = statusItem.button {
                let point = NSPoint(x: 0, y: btn.bounds.height + 3)
                menu.popUp(positioning: nil, at: point, in: btn)
            }
        } else {
            toggleAction()
        }
    }

    // MARK: Actions
    @objc private func toggleAction() {
        if isWorking { return }
        isWorking = true

        let wasOn = enabledState ?? false
        if let btn = statusItem.button {
            let workingState: IconState = wasOn ? .workingFromOn : .workingFromOff
            icons.apply(to: btn, state: workingState)
        }

        toggler.toggleAsync { [weak self] newValue in
            guard let self else { return }
            self.isWorking = false
            self.enabledState = newValue
            self.notify(enabled: newValue)
        }
    }

    // Launch at Login toggle
    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let wants = sender.state == .off
        do {
            try LaunchAtLogin.setEnabled(wants)
            sender.state = wants ? .on : .off
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Could not update Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            _ = LaunchAtLogin.openLoginItemsPane()
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: About
    @objc private func showAbout() { presentStandardAboutPanel() }

    // MARK: Notifications
    private func requestNotificationAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(enabled: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "Function Keys toggled"
        content.body = enabled
            ? "Enabled: F1, F2 act as standard function keys"
            : "Disabled: F1, F2 control hardware features"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    // MARK: Hotkey
    private func registerGlobalHotKey() {
        HotkeyConfig.register { [weak self] in
            self?.toggleAction()
        }
    }
}
