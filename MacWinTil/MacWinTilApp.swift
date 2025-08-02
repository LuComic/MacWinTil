//
//  MacWinTilApp.swift
//  MacWinTil
//
//  Created by Lukas Jääger on 02.08.2025.
//

import SwiftUI
import KeyboardShortcuts

@main
struct MacWinTilApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowManager: WindowManager!
    private var menuBarManager: MenuBarManager!
    private var keyboardShortcutsManager: KeyboardShortcutsManager!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon since this is a menubar-only app
        NSApp.setActivationPolicy(.accessory)
        
        // Check for clean start and prompt user if needed
        StartupManager.checkAndPromptForCleanStart { [weak self] shouldContinue in
            guard shouldContinue else {
                NSApp.terminate(nil)
                return
            }
            
            // Initialize managers after clean start
            self?.windowManager = WindowManager()
            self?.menuBarManager = MenuBarManager(windowManager: self!.windowManager)
            self?.keyboardShortcutsManager = KeyboardShortcutsManager(windowManager: self!.windowManager)
            
            print("MacWinTil started successfully!")
            print("Default shortcuts:")
            print("⌘⇧N - Create new space")
            print("⌘⇧1-5 - Switch to space 1-5")
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep running even when no windows are open
    }
}
