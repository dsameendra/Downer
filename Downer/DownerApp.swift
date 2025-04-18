//
//  DownerApp.swift
//  Downer
//
//  Created by Dumindu Sameendra on 2025-04-17.
//

import SwiftUI

@main
struct DownerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings {
            SettingsView().tint(.red)
        }

    }
}
