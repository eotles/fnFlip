//
//  LaunchAtLogin.swift
//  fnFlip
//
//  Copyright (c) 2025 Erkin Ötleş
//  Licensed under: MIT + Commons Clause (see LICENSE in repo root)
//  SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0
//

import Foundation
import ServiceManagement

enum LaunchAtLogin {
    // Label and on-disk name for the LaunchAgent
    private static let label = "eotles.fnFlip.launchagent"
    private static let plistName = "\(label).plist"

    // One-time marker so we only auto-enable on first run
    private static let defaultAppliedKey = "LaunchAtLoginDefaultApplied"

    // Paths
    private static var agentsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }
    private static var plistURL: URL { agentsDir.appendingPathComponent(plistName) }

    // Current app binary (this exact build)
    private static var currentExecutable: String {
        Bundle.main.executableURL?.path ?? ""
    }

    // MARK: Public API

    static var isEnabled: Bool {
        let uid = String(getuid())
        return run(["/bin/launchctl", "print", "gui/\(uid)/\(label)"]).status == 0
    }

    static func setEnabled(_ enabled: Bool) throws {
        try ensureAgentsDir()

        if enabled {
            try writePlist(programPath: currentExecutable)
            reloadAgent()
        } else {
            let uid = String(getuid())
            _ = run(["/bin/launchctl", "bootout", "gui/\(uid)/\(label)"])
            try? FileManager.default.removeItem(at: plistURL)
        }
    }

    /// Auto-enable at first launch only, if no prior choice and no agent present.
    static func enableByDefaultIfUnset() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: defaultAppliedKey) { return }

        // Mark as applied so we never do this again automatically
        defaults.set(true, forKey: defaultAppliedKey)

        // If an agent already exists, respect it and do nothing
        if FileManager.default.fileExists(atPath: plistURL.path) { return }

        // Best effort: enable silently
        try? setEnabled(true)
    }

    /// Try to self-heal the LaunchAgent if the app moved or the plist drifted.
    /// Returns true if a repair was performed (or an agent reload happened), false otherwise.
    @discardableResult
    static func repairIfNeeded() -> Bool {
        guard FileManager.default.fileExists(atPath: plistURL.path) else { return false }

        guard
            let data = try? Data(contentsOf: plistURL),
            let any = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            var dict = any as? [String: Any]
        else {
            try? writePlist(programPath: currentExecutable)
            reloadAgent()
            return true
        }

        let currentPath = currentExecutable
        var plistPath: String?

        if let args = dict["ProgramArguments"] as? [String], let first = args.first {
            plistPath = first
        } else if let prog = dict["Program"] as? String {
            plistPath = prog
        }

        if plistPath != currentPath {
            dict["ProgramArguments"] = [currentPath]
            dict["Program"] = nil

            if let newData = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0) {
                try? newData.write(to: plistURL, options: .atomic)
            } else {
                try? writePlist(programPath: currentPath)
            }

            reloadAgent()
            return true
        }

        if !isEnabled {
            reloadAgent()
            return true
        }

        return false
    }

    // Ventura convenience; harmless on older macOS
    @discardableResult
    static func openLoginItemsPane() -> Bool { openSettings() }

    @discardableResult
    static func openSettings() -> Bool {
        if #available(macOS 13.0, *) {
            do { try SMAppService.openSystemSettingsLoginItems(); return true } catch { return false }
        }
        return false
    }

    // MARK: LaunchAgent plumbing

    private static func ensureAgentsDir() throws {
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: agentsDir.path, isDirectory: &isDir) {
            try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        }
    }

    private static func writePlist(programPath: String) throws {
        let dict: [String: Any] = [
            "Label": label,
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
            "ProgramArguments": [programPath],
            "EnvironmentVariables": ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)
    }

    private static func reloadAgent() {
        let uid = String(getuid())
        _ = run(["/bin/launchctl", "bootout", "gui/\(uid)/\(label)"])
        _ = run(["/bin/launchctl", "bootstrap", "gui/\(uid)", plistURL.path])
        _ = run(["/bin/launchctl", "enable", "gui/\(uid)/\(label)"])
    }

    @discardableResult
    private static func run(_ args: [String]) -> (out: String, status: Int32) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: args[0])
        proc.arguments = Array(args.dropFirst())
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
            return (String(data: data, encoding: .utf8) ?? "", proc.terminationStatus)
        } catch {
            return ("\((error as NSError).localizedDescription)", -1)
        }
    }

    private static func makeError(_ msg: String) -> NSError {
        NSError(domain: "LaunchAtLogin", code: -3, userInfo: [NSLocalizedDescriptionKey: msg])
    }
}
