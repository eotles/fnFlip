//
//  AboutPanel.swift
//  fnFlip
//
//  Copyright (c) 2025 Erkin Ötleş
//  Licensed under: MIT + Commons Clause (see LICENSE in repo root)
//  SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0
//

import Cocoa

enum AboutPanel {
    static let licenseURLString = "https://github.com/eotles/fnFlip/blob/main/LICENSE"

    static func openLicense() {
        guard let url = URL(string: licenseURLString) else { return }
        NSWorkspace.shared.open(url)
    }
}

func presentStandardAboutPanel() {
    let credits = makeCreditsAttributedString(
"""
Switch how your function keys behave.

Toggle standard F1–F12 or Hardware Keys (brightness and volume).

License   ·   Shortcut: ⌘⌥F
"""
    )

    let opts: [NSApplication.AboutPanelOptionKey: Any] = [
        .credits: credits,
        .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
        .version: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    ]
    NSApp.orderFrontStandardAboutPanel(options: opts)
    NSApp.activate(ignoringOtherApps: true)
}

// MARK: - Helpers

private func makeCreditsAttributedString(_ text: String) -> NSAttributedString {
    let p = NSMutableParagraphStyle()
    p.lineBreakMode = .byWordWrapping
    p.alignment = .left
    p.paragraphSpacing = 4

    // Use a smaller font so the stock panel won’t scroll
    let base: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: p
    ]

    let s = NSMutableAttributedString(string: text, attributes: base)

    // Make just the word "License" clickable
    let linkTitle = "License"
    if let url = URL(string: AboutPanel.licenseURLString) {
        let range = (s.string as NSString).range(of: linkTitle)
        if range.location != NSNotFound {
            s.addAttributes([.link: url], range: range)
        }
    }
    return s
}
