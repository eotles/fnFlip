//
//  FnFlipApp.swift
//  fnFlip
//
//  Copyright (c) 2025 Erkin Ötleş
//  Licensed under: MIT + Commons Clause (see LICENSE in repo root)
//  SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0
//

import SwiftUI

@main
struct fnFlipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { EmptyView() } // no visible settings window
    }
}
