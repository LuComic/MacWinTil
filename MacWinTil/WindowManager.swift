//
//  WindowManager.swift
//  MacWinTil
//
//  Created by Lukas Jääger on 02.08.2025.
//

import Foundation
import AppKit
import ApplicationServices

class WindowManager: ObservableObject {
    @Published var spaces: [Int: [String]] = [1: []]
    @Published var currentSpace: Int = 1
    
    private var windowObserver: AXObserver?
    private var layoutEnforcementTimer: Timer?
    
    init() {
        requestAccessibilityPermissions()
        setupWindowObserver()
        startLayoutEnforcement()
        
        // Print config info on startup
        ConfigManager.shared.printConfigInfo()
    }
    
    private func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !trusted {
            print("Accessibility permissions required for window management")
        }
    }
    
    private func setupWindowObserver() {
        // Monitor for app launches
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                print("App launched: \(app.localizedName ?? "Unknown")")
                // Add a small delay to let the app fully launch before handling
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.handleApplicationLaunched(app)
                }
            }
        }
        
        // Monitor for app activation (when apps get focus)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.handleApplicationActivated(app)
            }
        }
        
        // Monitor for app termination
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.handleApplicationTerminated(app)
            }
        }
        
        // Start monitoring for window closes
        startWindowCloseMonitoring()
    }
    
    private func handleApplicationLaunched(_ app: NSRunningApplication) {
        guard let appName = app.localizedName else { return }
        
        // Skip our own app
        if appName == "MacWinTil" { return }
        
        // Check if app is excluded in config
        if ConfigManager.shared.isAppExcluded(appName) {
            print("App \(appName) is excluded by config, skipping")
            return
        }
        
        // Skip only essential system processes, be more permissive with user apps
        if let bundleId = app.bundleIdentifier {
            // Only exclude core system processes that should never be managed
            let coreSystemApps = [
                "com.apple.finder",
                "com.apple.dock",
                "com.apple.systemuiserver",
                "com.apple.controlcenter",
                "com.apple.loginwindow",
                "com.apple.WindowServer"
            ]
            
            if coreSystemApps.contains(bundleId) { return }
        }
        
        // Only handle regular applications (not background processes)
        if app.activationPolicy != .regular { return }
        
        print("Handling app launch: \(appName) (\(app.bundleIdentifier ?? "no bundle ID"))")
        
        // Check if app is already running in another space
        let existingSpace = findSpaceContaining(appName: appName)
        
        if let existingSpace = existingSpace, existingSpace != currentSpace {
            // App exists in another space - activate and create new window
            print("App \(appName) exists in space \(existingSpace), creating new window for space \(currentSpace)")
            activateAppAndCreateNewWindow(app)
        }
        
        // Add app to current space if not already present
        if !spaces[currentSpace, default: []].contains(appName) {
            spaces[currentSpace, default: []].append(appName)
            
            print("Added \(appName) to space \(currentSpace)")
            
            // Force immediate arrangement
            arrangeWindowsInCurrentSpace()
            
            // Single retry after delay to override app's position memory (reduced to avoid flashing)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.arrangeWindowsInCurrentSpace()
            }
        }
    }
    
    private func handleApplicationActivated(_ app: NSRunningApplication) {
        guard let appName = app.localizedName else { return }
        
        // Skip our own app
        if appName == "MacWinTil" { return }
        
        // Check if app is excluded in config
        if ConfigManager.shared.isAppExcluded(appName) {
            print("App \(appName) is excluded by config, skipping")
            return
        }
        
        // Skip only essential system processes, be more permissive with user apps
        if let bundleId = app.bundleIdentifier {
            // Only exclude core system processes that should never be managed
            let coreSystemApps = [
                "com.apple.finder",
                "com.apple.dock",
                "com.apple.systemuiserver",
                "com.apple.controlcenter",
                "com.apple.loginwindow",
                "com.apple.WindowServer"
            ]
            
            if coreSystemApps.contains(bundleId) { return }
        }
        
        // Only handle regular applications (not background processes)
        if app.activationPolicy != .regular { return }
        
        print("Detected app activation: \(appName) (\(app.bundleIdentifier ?? "no bundle ID"))")
        
        // Check if app is already running in another space
        let existingSpace = findSpaceContaining(appName: appName)
        
        if let existingSpace = existingSpace, existingSpace != currentSpace {
            // App exists in another space - activate and create new window
            print("App \(appName) exists in space \(existingSpace), creating new window for space \(currentSpace)")
            activateAppAndCreateNewWindow(app)
        }
        
        // Add app to current space if not already present
        if !spaces[currentSpace, default: []].contains(appName) {
            spaces[currentSpace, default: []].append(appName)
            
            // Force immediate arrangement
            arrangeWindowsInCurrentSpace()
            
            // Single retry after delay to override app's position memory (reduced to avoid flashing)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.arrangeWindowsInCurrentSpace()
            }
        }
    }
    
    private func handleApplicationTerminated(_ app: NSRunningApplication) {
        guard let appName = app.localizedName else { return }
        
        // Remove app from all spaces
        for spaceNumber in spaces.keys {
            spaces[spaceNumber]?.removeAll { $0 == appName }
        }
        
        // Rearrange windows in current space if needed
        arrangeWindowsInCurrentSpace()
        
        print("App terminated: \(appName)")
    }
    
    private func startLayoutEnforcement() {
        // Less aggressive periodic enforcement to avoid flashing
        layoutEnforcementTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            // Only enforce if there are apps in current space
            if let self = self, !self.spaces[self.currentSpace, default: []].isEmpty {
                self.arrangeWindowsInCurrentSpace()
            }
        }
    }
    
    private func startWindowCloseMonitoring() {
        // Monitor for window close events by checking window count changes
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkForClosedWindows()
        }
    }
    
    private func checkForClosedWindows() {
        // Check each app in current space to see if windows were closed
        let currentApps = spaces[currentSpace, default: []]
        var appsToRemove: [String] = []
        
        for appName in currentApps {
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) {
                let appRef = AXUIElementCreateApplication(app.processIdentifier)
                var windowList: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowList)
                
                if result == .success, let windows = windowList as? [AXUIElement] {
                    // Check if app has any visible (non-minimized) windows
                    let hasVisibleWindows = windows.contains { window in
                        var minimized: CFTypeRef?
                        AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)
                        if let isMinimized = minimized as? Bool {
                            return !isMinimized
                        }
                        return true // Assume visible if we can't determine
                    }
                    
                    // If no visible windows, remove from current space
                    if !hasVisibleWindows {
                        appsToRemove.append(appName)
                    }
                } else {
                    // If we can't get windows, assume app should be removed
                    appsToRemove.append(appName)
                }
            } else {
                // App is no longer running
                appsToRemove.append(appName)
            }
        }
        
        // Remove apps that have no visible windows and re-arrange
        for appName in appsToRemove {
            spaces[currentSpace]?.removeAll { $0 == appName }
            print("Removed \(appName) from space \(currentSpace) - no visible windows")
        }
        
        // Re-arrange if any apps were removed
        if !appsToRemove.isEmpty {
            arrangeWindowsInCurrentSpace()
        }
    }
    
    func createNewSpace() {
        // Minimize all windows in current space
        minimizeAllWindowsInCurrentSpace()
        
        // Create new space
        let newSpaceNumber = (spaces.keys.max() ?? 0) + 1
        spaces[newSpaceNumber] = []
        currentSpace = newSpaceNumber
    }
    
    func switchToSpace(_ spaceNumber: Int) {
        guard spaces[spaceNumber] != nil else { return }
        
        // Minimize current space windows
        minimizeAllWindowsInCurrentSpace()
        
        // Switch to new space
        currentSpace = spaceNumber
        
        // Restore windows in target space
        restoreWindowsInSpace(spaceNumber)
    }
    
    func closeCurrentSpace() {
        // Don't close space 1 (always keep at least one space)
        guard currentSpace != 1 && spaces.count > 1 else {
            print("⚠️ Cannot close space \(currentSpace): Must keep at least space 1")
            return
        }
        
        // Get apps in current space
        let appsInCurrentSpace = spaces[currentSpace, default: []]
        
        // Close all windows in current space
        for appName in appsInCurrentSpace {
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) {
                closeAppWindows(app)
            }
        }
        
        // Remove the space
        spaces.removeValue(forKey: currentSpace)
        
        // Switch to the previous space or space 1
        let targetSpace = currentSpace > 1 ? currentSpace - 1 : 1
        
        // Find the closest existing space
        let availableSpaces = spaces.keys.sorted()
        let closestSpace = availableSpaces.first { $0 >= targetSpace } ?? availableSpaces.last ?? 1
        
        currentSpace = closestSpace
        
        // Restore windows in the new current space
        restoreWindowsInSpace(currentSpace)
        
        print("✅ Closed space and switched to space \(currentSpace)")
    }
    
    private func minimizeAllWindowsInCurrentSpace() {
        let apps = spaces[currentSpace, default: []]
        
        for appName in apps {
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) {
                minimizeAppWindows(app)
            }
        }
    }
    
    private func restoreWindowsInSpace(_ spaceNumber: Int) {
        let apps = spaces[spaceNumber, default: []]
        
        for appName in apps {
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) {
                restoreAppWindows(app)
            }
        }
        
        // Arrange windows after restoration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.arrangeWindowsInCurrentSpace()
        }
    }
    
    private func minimizeAppWindows(_ app: NSRunningApplication) {
        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        
        var windowList: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowList)
        
        if result == .success, let windows = windowList as? [AXUIElement] {
            for window in windows {
                var minimized: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)
                
                if let isMinimized = minimized as? Bool, !isMinimized {
                    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, true as CFTypeRef)
                }
            }
        }
    }
    
    private func restoreAppWindows(_ app: NSRunningApplication) {
        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        
        var windowList: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowList)
        
        if result == .success, let windows = windowList as? [AXUIElement] {
            for window in windows {
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
            }
        }
    }
    
    private func closeAppWindows(_ app: NSRunningApplication) {
        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        
        var windowList: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowList)
        
        if result == .success, let windows = windowList as? [AXUIElement] {
            for window in windows {
                // Try to close the window using the close button
                var closeButton: CFTypeRef?
                let closeResult = AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &closeButton)
                
                if closeResult == .success, let button = closeButton {
                    AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
                } else {
                    // Fallback: minimize the window if we can't close it
                    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, true as CFTypeRef)
                }
            }
        }
    }
    
    private func arrangeWindowsInCurrentSpace() {
        let apps = spaces[currentSpace, default: []]
        guard !apps.isEmpty else { return }
        
        // Get screen frame and account for menubar
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame // This excludes menubar and dock
        
        // Ensure windows start from the bottom of the visible area
        let adjustedFrame = NSRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY, // This should be the bottom of the visible area
            width: visibleFrame.width,
            height: visibleFrame.height
        )
        
        print("Screen frame: \(screenFrame)")
        print("Visible frame: \(visibleFrame)")
        print("Adjusted frame: \(adjustedFrame)")
        
        let frames = TilingLayout.calculateFrames(for: apps.count, in: adjustedFrame)
        
        for (index, appName) in apps.enumerated() {
            guard index < frames.count else { break }
            
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) {
                setWindowFrame(app: app, frame: frames[index], screenHeight: screenFrame.height)
            }
        }
    }
    
    private func findSpaceContaining(appName: String) -> Int? {
        for (spaceNumber, apps) in spaces {
            if apps.contains(appName) {
                return spaceNumber
            }
        }
        return nil
    }
    
    private func activateAppAndCreateNewWindow(_ app: NSRunningApplication) {
        guard let appName = app.localizedName else { return }
        
        // First, activate the app (this will restore it from minimized state)
        app.activate(options: [])
        
        // Wait a moment for activation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Try to create new window using different methods
            let newWindowShortcut = ConfigManager.shared.getShortcut(for: "newWindowShortcut") ?? "⌘N"
            let (key, modifiers) = self.parseShortcutForAppleScript(newWindowShortcut)
            
            let script = """
            tell application "\(appName)"
                activate
            end tell
            delay 0.2
            tell application "System Events"
                keystroke "\(key)" using \(modifiers)
            end tell
            """
            
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: script) {
                scriptObject.executeAndReturnError(&error)
                if error == nil {
                    print("Successfully created new window for \(appName) using Cmd+N")
                } else {
                    print("Failed to create new window for \(appName): \(error!)")
                    // Try alternative method
                    self.tryAlternativeWindowCreation(for: appName)
                }
            }
        }
    }
    
    private func tryAlternativeWindowCreation(for appName: String) {
        let alternativeScript = "tell application \"\(appName)\" to make new document"
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: alternativeScript) {
            scriptObject.executeAndReturnError(&error)
            if error == nil {
                print("Successfully created new document for \(appName)")
            } else {
                print("Could not create new window/document for \(appName)")
            }
        }
    }
    
    private func setWindowFrame(app: NSRunningApplication, frame: NSRect, screenHeight: CGFloat) {
        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        
        var windowList: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowList)
        
        if result == .success, let windows = windowList as? [AXUIElement] {
            // Position all windows of the app, not just the first one
            for window in windows {
                // Check if window is minimized and restore it first
                var minimized: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)
                if let isMinimized = minimized as? Bool, isMinimized {
                    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
                }
                
                var origin = frame.origin
                var size = frame.size
                
                // Convert Y-coordinate from bottom-left to top-left origin
                origin.y = screenHeight - frame.origin.y - frame.height
                
                let position = AXValueCreate(.cgPoint, &origin)
                let sizeValue = AXValueCreate(.cgSize, &size)
                
                if let position = position, let sizeValue = sizeValue {
                    // Set position and size (reduced attempts to avoid flashing)
                    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
                    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
                    
                    // Don't bring to front to avoid flashing between apps
                }
            }
        }
    }
    
    func removeAppFromCurrentSpace(_ appName: String) {
        spaces[currentSpace]?.removeAll { $0 == appName }
        arrangeWindowsInCurrentSpace()
    }
    
    // MARK: - App Exclusion Toggle
    func toggleCurrentAppExclusion() {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let appName = frontmostApp.localizedName else {
            print("⚠️ Could not get frontmost application")
            return
        }
        
        // Skip our own app
        if appName == "MacWinTil" {
            print("⚠️ Cannot exclude MacWinTil itself")
            return
        }
        
        let configManager = ConfigManager.shared
        
        if configManager.isAppExcluded(appName) {
            // App is excluded, include it back
            configManager.removeExcludedApp(appName)
            
            // Add to current space if not already present
            if !spaces[currentSpace, default: []].contains(appName) {
                spaces[currentSpace, default: []].append(appName)
                print("✅ \(appName) included in tiling and added to space \(currentSpace)")
                
                // Arrange windows immediately
                arrangeWindowsInCurrentSpace()
            } else {
                print("✅ \(appName) included in tiling (already in space \(currentSpace))")
            }
        } else {
            // App is not excluded, exclude it
            configManager.addExcludedApp(appName)
            
            // Remove from all spaces
            for spaceNumber in spaces.keys {
                if let index = spaces[spaceNumber]?.firstIndex(of: appName) {
                    spaces[spaceNumber]?.remove(at: index)
                    print("🚫 Removed \(appName) from space \(spaceNumber)")
                }
            }
            
            print("✅ \(appName) excluded from tiling")
            
            // Rearrange current space
            arrangeWindowsInCurrentSpace()
        }
    }
    
    // MARK: - Helper Methods
    private func parseShortcutForAppleScript(_ shortcutString: String) -> (key: String, modifiers: String) {
        var modifiers: [String] = []
        var keyChar: Character?
        
        for char in shortcutString {
            switch char {
            case "⌘": // Command
                modifiers.append("command down")
            case "⌥": // Option
                modifiers.append("option down")
            case "⇧": // Shift
                modifiers.append("shift down")
            case "⌃": // Control
                modifiers.append("control down")
            default:
                keyChar = char
            }
        }
        
        let key = keyChar?.lowercased() ?? "n"
        let modifierString = modifiers.joined(separator: " and ")
        
        return (key: String(key), modifiers: modifierString.isEmpty ? "{}" : "{\(modifierString)}")
    }
}
