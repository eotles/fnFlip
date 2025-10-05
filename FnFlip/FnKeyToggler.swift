//
//  FnKeyToggler.swift
//  fnFlip
//
//  Copyright (c) 2025 Erkin Ötleş
//  Licensed under: MIT + Commons Clause (see LICENSE in repo root)
//  SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0
//

import Foundation
import CoreFoundation

/// Reads and writes the "Use F1, F2, etc. keys as standard function keys" preference.
/// All preference I/O happens off the main thread on a private serial queue.
/// Uses CFPreferences directly to avoid forking shells and to prevent OS pauses.
final class FnKeyToggler {

    // Private serial queue so reads and writes are ordered and never block UI
    private let workQueue = DispatchQueue(label: "com.eotles.fnflip.toggler")

    // MARK: Public API

    /// Asynchronously reads the current value.
    /// The completion is invoked on the main queue.
    func readAsync(_ completion: @escaping (Bool) -> Void) {
        workQueue.async {
            let value = Self.readSync()
            DispatchQueue.main.async { completion(value) }
        }
    }

    /// Toggles the setting and returns the new value in the completion.
    /// All work happens off the main thread, completion is on the main thread.
    func toggleAsync(_ completion: @escaping (Bool) -> Void) {
        workQueue.async {
            let newVal = Self.toggleSync()
            DispatchQueue.main.async { completion(newVal) }
        }
    }

    // MARK: Private synchronous helpers

    private static let key: CFString = "com.apple.keyboard.fnState" as CFString

    /// Read current value. Returns true when standard F1..F12 is enabled.
    private static func readSync() -> Bool {
        // Read from the global domain for current user, any host
        if let cfVal = CFPreferencesCopyValue(
            key,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? Bool {
            return cfVal
        }

        // Fallback to defaults(1) once if CFPreferences has nothing
        let r = run("/usr/bin/defaults", args: ["read", "-g", "com.apple.keyboard.fnState"])
        if r.status == 0,
           let out = r.stdout?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            return out == "1" || out == "true" || out == "yes"
        }
        return false
    }

    /// Toggle the setting and return the new state.
    /// Uses CFPreferences, then nudges the system to pick up changes.
    private static func toggleSync() -> Bool {
        let current = readSync()
        let newVal = !current

        // Write global and currentHost variants via CFPreferences
        CFPreferencesSetValue(
            key, newVal as CFBoolean,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        CFPreferencesSynchronize(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )

        // Also update the per-host copy since macOS sometimes consults it
        CFPreferencesSetValue(
            key, newVal as CFBoolean,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        CFPreferencesSynchronize(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )

        // Light nudge so the UI updates without killing cfprefsd
        _ = run("/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings",
                args: ["-u"])

        return newVal
    }

    // MARK: tiny shell helper (non-blocking for UI, used on background queue)
    private struct Result { let stdout: String?; let stderr: String?; let status: Int32 }

    @discardableResult
    private static func run(_ cmd: String, args: [String]) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cmd)
        p.arguments = args
        let out = Pipe(); let err = Pipe()
        p.standardOutput = out; p.standardError = err
        do { try p.run() } catch {
            return Result(stdout: nil, stderr: "\(error)", status: -1)
        }
        p.waitUntilExit()
        let outStr = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        let errStr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        return Result(stdout: outStr, stderr: errStr, status: p.terminationStatus)
    }
}
