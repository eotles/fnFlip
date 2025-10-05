//
//  StatusMenuBuilder.swift
//  fnFlip
//
//  Copyright (c) 2025 Erkin Ötleş
//  Licensed under: MIT + Commons Clause (see LICENSE in repo root)
//  SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0
//

import Cocoa

enum StatusMenuBuilder {

    private enum Tag {
        static let header = 900
        static let toggle = 901
        static let launch = 902
        static let about  = 903
        static let quit   = 904
    }

    // Build a new menu wired to the provided target and actions.
    static func build(
        isEnabled: Bool,
        isLaunchEnabled: Bool,
        toggleAction: Selector,
        launchAtLoginAction: Selector,
        aboutAction: Selector,
        quitAction: Selector,
        target: AnyObject
    ) -> NSMenu {

        let m = NSMenu()
        m.autoenablesItems = false

        // 1) Header (disabled, secondary style)
        let header = NSMenuItem(title: headerTitle(isEnabled: isEnabled), action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.attributedTitle = attributedHeader(header.title)
        header.tag = Tag.header
        m.addItem(header)

        // 2) Switch item (⌥⌘F)
        let toggle = NSMenuItem(
            title: titleForToggle(isEnabled: isEnabled),
            action: toggleAction,
            keyEquivalent: "f"
        )
        toggle.keyEquivalentModifierMask = [.command, .option]
        toggle.target = target
        toggle.tag = Tag.toggle
        m.addItem(toggle)

        m.addItem(NSMenuItem.separator())

        // 3) Launch at Login (checkmark)
        let launch = NSMenuItem(title: "Launch at Login", action: launchAtLoginAction, keyEquivalent: "")
        launch.target = target
        launch.state = isLaunchEnabled ? .on : .off
        launch.tag = Tag.launch
        m.addItem(launch)

        m.addItem(NSMenuItem.separator())

        // 4) About
        let about = NSMenuItem(title: "About fnFlip…", action: aboutAction, keyEquivalent: "")
        about.target = target
        about.tag = Tag.about
        m.addItem(about)

        m.addItem(NSMenuItem.separator())

        // 5) Quit (⌘Q)
        let quit = NSMenuItem(title: "Quit", action: quitAction, keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        quit.target = target
        quit.tag = Tag.quit
        m.addItem(quit)

        return m
    }

    // Update titles and checkmarks on an existing menu.
    static func refresh(_ menu: NSMenu, isEnabled: Bool, isLaunchEnabled: Bool) {
        if let header = menu.item(withTag: Tag.header) {
            header.title = headerTitle(isEnabled: isEnabled)
            header.attributedTitle = attributedHeader(header.title)
        }
        if let toggle = menu.item(withTag: Tag.toggle) {
            toggle.title = titleForToggle(isEnabled: isEnabled)
        }
        if let launch = menu.item(withTag: Tag.launch) {
            launch.state = isLaunchEnabled ? .on : .off
        }
        menu.update()
    }

    // MARK: helpers

    private static func titleForToggle(isEnabled: Bool) -> String {
        // isEnabled means Standard F-keys mode is active
        return isEnabled ? "Switch to Hardware Keys" : "Switch to Standard F1, F2, etc."
    }

    private static func headerTitle(isEnabled: Bool) -> String {
        return isEnabled
        ? "Current: Standard F1, F2, etc."
        : "Current: Hardware Keys (brightness and volume)"
    }

    private static func attributedHeader(_ s: String) -> NSAttributedString {
        NSAttributedString(
            string: s,
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            ]
        )
    }
}
