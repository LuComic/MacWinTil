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
    private var isBringingAllToFront = false // Flag to prevent recursive activation
    private var originallyActivatedApp: NSRunningApplication? // Store the app user originally clicked
    private var lastActivatedApp: String? // Track the previously active app
    
    // Edit mode state
    @Published var isEditMode = false
    private var editModeKeyMonitor: Any?
    
    init() {
        requestAccessibilityPermissions()
        setupWindowObserver()
        startLayoutEnforcement()
        
        // Print config info on startup
        ConfigManager.shared.printConfigInfo()
    }
    
    deinit {
        removeEditModeKeyMonitor()
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
            // Still update lastActivatedApp for context tracking
            lastActivatedApp = appName
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
            // Check context BEFORE adding to space to get accurate previous state
            let currentSpaceApps = spaces[currentSpace, default: []]
            let wasLastAppTiled = lastActivatedApp != nil && currentSpaceApps.contains(lastActivatedApp!)
            
            // Now add the app to the space
            spaces[currentSpace, default: []].append(appName)
            print("Added \(appName) to space \(currentSpace)")
            
            print("Debug Launch: New app: \(appName), Last app: \(lastActivatedApp ?? "none"), Was last tiled: \(wasLastAppTiled)")
            
            // If launching from excluded context, bring all tiled windows to front
            if !wasLastAppTiled && !isBringingAllToFront {
                print("Launching tiled app from excluded context, bringing all tiled windows to front")
                originallyActivatedApp = app
                bringAllTiledWindowsToFront()
            } else {
                print("Launching from tiled context, normal arrangement")
                // Normal tiling arrangement
                arrangeWindowsInCurrentSpace()
                
                // Single retry after delay to override app's position memory
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.arrangeWindowsInCurrentSpace()
                }
            }
            
            // Update last activated app to the newly launched app
            lastActivatedApp = appName
        }
    }
    
    private func handleApplicationActivated(_ app: NSRunningApplication) {
        guard let appName = app.localizedName else { return }
        
        // Skip our own app
        if appName == "MacWinTil" { return }
        
        // Check if app is excluded in config
        if ConfigManager.shared.isAppExcluded(appName) {
            print("App \(appName) is excluded by config, skipping")
            // Still update lastActivatedApp for context tracking
            lastActivatedApp = appName
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
        
        // Check if this app is in the current space (tiled)
        let currentSpaceApps = spaces[currentSpace, default: []]
        let isAppInCurrentSpace = currentSpaceApps.contains(appName)
        
        // Check if the previously active app was also tiled
        let wasLastAppTiled = lastActivatedApp != nil && currentSpaceApps.contains(lastActivatedApp!)
        
        print("Debug: Current app: \(appName), Last app: \(lastActivatedApp ?? "none"), Was last tiled: \(wasLastAppTiled), Current is tiled: \(isAppInCurrentSpace)")
        
        // Only bring all to front if:
        // 1. Current app is tiled AND
        // 2. Previous app was NOT tiled (switching from non-tiled to tiled context) AND
        // 3. We're not already bringing all to front
        if isAppInCurrentSpace && !wasLastAppTiled && !isBringingAllToFront {
            print("Switching from non-tiled to tiled app (\(appName)), bringing all tiled windows to front")
            // Save the originally activated app
            originallyActivatedApp = app
            bringAllTiledWindowsToFront()
        } else if isAppInCurrentSpace {
            print("Staying within tiled context (\(appName)), no need to bring all to front")
        } else {
            print("App \(appName) is not tiled, no action needed")
        }
        
        // Update the last activated app after the logic
        lastActivatedApp = appName
        
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
    
    // MARK: - Window Management
    private func bringAllTiledWindowsToFront() {
        let currentSpaceApps = spaces[currentSpace, default: []]
        
        // Set flag to prevent recursive activation
        isBringingAllToFront = true
        
        // Bring each tiled app to front with a small delay to avoid conflicts
        for (index, appName) in currentSpaceApps.enumerated() {
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) {
                // Use a small delay between activations to ensure proper ordering
                let delay = Double(index) * 0.02 // 20ms between each app
                
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    // Activate the app to bring its windows to front
                    app.activate(options: [])
                    print("Brought \(appName) to front (delay: \(delay)s)")
                }
            }
        }
        
        // After bringing all apps to front, rearrange to ensure proper tiling
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(currentSpaceApps.count) * 0.02 + 0.05) {
            self.arrangeWindowsInCurrentSpace()
            // Clear flag after all activations are complete
            self.isBringingAllToFront = false
            
            // Now activate the originally clicked app
            if let originalApp = self.originallyActivatedApp {
                // Temporarily set flag to prevent re-triggering the loop
                self.isBringingAllToFront = true
                originalApp.activate(options: [])
                if let appName = originalApp.localizedName {
                    print("Re-activated original app: \(appName)")
                }
                // Clear the stored app and flag after a short delay
                self.originallyActivatedApp = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.isBringingAllToFront = false
                }
            }
            
            print("Finished bringing all tiled windows to front")
        }
    }
    
    // MARK: - App Exclusion Toggle
    func enterEditMode() {
        print("🔧 Entering edit mode")
        
        // Store the currently active app
        originallyActivatedApp = NSWorkspace.shared.frontmostApplication
        
        isEditMode = true
        
        // Activate our app first
        NSApp.activate(ignoringOtherApps: true)
        
        // Small delay to ensure our app is active before monitoring keys
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.setupEditModeKeyMonitor()
            
            // After setting up the monitor, reactivate the original app
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                if #available(macOS 14.0, *) {
                    self?.originallyActivatedApp?.activate()
                } else {
                    self?.originallyActivatedApp?.activate(options: .activateIgnoringOtherApps)
                }
            }
        }
    }
    
    private func exitEditMode() {
        print("🔧 Exiting edit mode")
        isEditMode = false
        removeEditModeKeyMonitor()
        
        // Reactivate the original app when exiting edit mode
        if let app = originallyActivatedApp {
            DispatchQueue.main.async { [weak self] in
                if #available(macOS 14.0, *) {
                    app.activate()
                } else {
                    app.activate(options: .activateIgnoringOtherApps)
                }
                // Clear the reference to avoid potential retain cycles
                self?.originallyActivatedApp = nil
            }
        }
    }
    
    private func setupEditModeKeyMonitor() {
        // Remove existing monitor if any
        removeEditModeKeyMonitor()
        
        // First, activate the app to ensure we receive key events
        NSApp.activate(ignoringOtherApps: true)
        
        // Use a global monitor to catch events even when the app isn't active
        editModeKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isEditMode else { return }
            
            // Get the key without modifiers
            guard let chars = event.charactersIgnoringModifiers?.lowercased(),
                  let key = chars.unicodeScalars.first?.value else {
                self.exitEditMode()
                return
            }
            
            // Convert to character and handle the key
            let char = Character(UnicodeScalar(key)!)
            
            // Process the key press on the main thread
            DispatchQueue.main.async {
                self.handleEditModeKeyPress(char)
            }
        }
    }
    
    private func handleEditModeKeyPress(_ char: Character) {
        print("🔑 Edit mode key pressed: \(char)")
        
        switch char {
        case "e":
            toggleCurrentAppExclusion()
            exitEditMode()
        case "h":
            moveCurrentWindowLeft()
        case "j":
            moveCurrentWindowDown()
        case "k":
            moveCurrentWindowUp()
        case "l":
            moveCurrentWindowRight()
        default:
            // Any other key exits edit mode
            print("❌ Unknown key, exiting edit mode")
            exitEditMode()
        }
    }
    
    private func removeEditModeKeyMonitor() {
        if let monitor = editModeKeyMonitor {
            NSEvent.removeMonitor(monitor)
            editModeKeyMonitor = nil
        }
    }
    
    private func toggleCurrentAppExclusion() {
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
    
    // MARK: - Window Movement Methods
    private func moveCurrentWindowLeft() {
        moveCurrentWindow(direction: .left)
    }
    
    private func moveCurrentWindowRight() {
        moveCurrentWindow(direction: .right)
    }
    
    private func moveCurrentWindowUp() {
        moveCurrentWindow(direction: .up)
    }
    
    private func moveCurrentWindowDown() {
        moveCurrentWindow(direction: .down)
    }
    
    private enum MoveDirection {
        case left, right, up, down
    }
    
    private func moveCurrentWindow(direction: MoveDirection) {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let appName = frontmostApp.localizedName else {
            print("⚠️ Could not get frontmost application")
            return
        }
        
        var currentSpaceApps = spaces[currentSpace, default: []]
        guard let currentIndex = currentSpaceApps.firstIndex(of: appName) else {
            print("⚠️ \(appName) not found in current space")
            return
        }
        
        let targetIndex: Int
        let directionName: String
        
        switch direction {
        case .left, .right:
            targetIndex = getTargetIndexForHorizontalMove(
                currentIndex: currentIndex,
                direction: direction,
                totalApps: currentSpaceApps.count
            )
            directionName = direction == .left ? "left" : "right"
        case .up, .down:
            targetIndex = getTargetIndexForVerticalMove(
                currentIndex: currentIndex,
                direction: direction,
                totalApps: currentSpaceApps.count
            )
            directionName = direction == .up ? "up" : "down"
        }
        
        // Only swap if the target index is different and valid
        if targetIndex != currentIndex && targetIndex >= 0 && targetIndex < currentSpaceApps.count {
            // Store the current frontmost app to restore focus later
            let wasFrontmostApp = NSWorkspace.shared.frontmostApplication
            
            // Perform the swap
            currentSpaceApps.swapAt(currentIndex, targetIndex)
            spaces[currentSpace] = currentSpaceApps
            
            print("🔄 Moved \(appName) \(directionName) (from position \(currentIndex) to \(targetIndex))")
            
            // Rearrange windows to reflect the new order
            arrangeWindowsInCurrentSpace()
            
            // Keep the same app focused after moving
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if #available(macOS 14.0, *) {
                    wasFrontmostApp?.activate()
                } else {
                    wasFrontmostApp?.activate(options: .activateIgnoringOtherApps)
                }
            }
        } else {
            print("ℹ️ No movement - already at the \(directionName) edge")
        }
    }
    
    private func getTargetIndexForHorizontalMove(currentIndex: Int, direction: MoveDirection, totalApps: Int) -> Int {
        guard totalApps > 1 else { return currentIndex }
        
        // Special handling for 3 windows (left half, top right, bottom right)
        if totalApps == 3 {
            print("🔄 3-window layout detected in horizontal move")
            switch (currentIndex, direction) {
            // Left half (0) - can only move right (to 1)
            case (0, .right): return 1
            
            // Top right (1) - can move left (to 0)
            case (1, .left): return 0
            
            // Bottom right (2) - can move left (to 0)
            case (2, .left): return 0
            
            // All other cases - no movement
            default: 
                print("No horizontal movement - invalid direction for current window position")
                return currentIndex
            }
        }
        
        // For other numbers of windows, use the grid-based approach
        let maxAppsPerRow = totalApps <= 4 ? 2 : Int(ceil(sqrt(Double(totalApps))))
        let appsPerRow = min(maxAppsPerRow, totalApps)
        
        let currentRow = currentIndex / appsPerRow
        let currentCol = currentIndex % appsPerRow
        let totalRows = (totalApps + appsPerRow - 1) / appsPerRow
        
        print("🔄 Horizontal move: index=\(currentIndex), row=\(currentRow), col=\(currentCol), total=\(totalApps)")
        
        let targetCol: Int
        switch direction {
        case .left:
            // Move left, wrap around to the end of the row if at the start
            targetCol = currentCol > 0 ? currentCol - 1 : appsPerRow - 1
        case .right:
            // Move right, wrap around to the start of the row if at the end
            targetCol = (currentCol + 1) % appsPerRow
        default:
            return currentIndex
        }
        
        // Calculate the target index in the same row but different column
        var targetIndex = currentRow * appsPerRow + targetCol
        
        // Ensure the target index is within bounds
        targetIndex = min(targetIndex, totalApps - 1)
        
        print("   → Moving to: index=\(targetIndex), row=\(targetIndex/appsPerRow), col=\(targetIndex%appsPerRow)")
        return targetIndex
    }
    
    private func getTargetIndexForVerticalMove(currentIndex: Int, direction: MoveDirection, totalApps: Int) -> Int {
        guard totalApps > 1 else { return currentIndex }
        
        // Special handling for 3 windows (left half, top right, bottom right)
        if totalApps == 3 {
            print("🔄 3-window layout detected")
            switch (currentIndex, direction) {
            // Left half (0) - can only move right (to 1)
            case (0, .right): return 1
            
            // Top right (1) - can move left (to 0) or down (to 2)
            case (1, .left): return 0
            case (1, .down): return 2
            
            // Bottom right (2) - can move left (to 0) or up (to 1)
            case (2, .left): return 0
            case (2, .up): return 1
            
            // All other cases - no movement
            default: 
                print("No movement - invalid direction for current window position")
                return currentIndex
            }
        }
        
        // For other numbers of windows, use the grid-based approach
        let appsPerRow = min(2, totalApps) // Max 2 apps per row for small numbers
        let currentRow = currentIndex / appsPerRow
        let currentCol = currentIndex % appsPerRow
        let totalRows = (totalApps + appsPerRow - 1) / appsPerRow
        
        print("🔄 Vertical move: index=\(currentIndex), row=\(currentRow), col=\(currentCol), total=\(totalApps), rows=\(totalRows), cols=\(appsPerRow)")
        
        var targetRow = currentRow
        switch direction {
        case .up:
            if currentRow > 0 {
                targetRow = currentRow - 1
            } else {
                // If at top row, wrap to bottom row
                targetRow = totalRows - 1
            }
        case .down:
            if currentRow < totalRows - 1 {
                targetRow = currentRow + 1
            } else {
                // If at bottom row, wrap to top row
                targetRow = 0
            }
        default:
            return currentIndex
        }
        
        // Calculate the target index in the same column
        var targetIndex = targetRow * appsPerRow + currentCol
        
        // If the target position is beyond the total number of apps,
        // adjust to the last position in the target row
        if targetIndex >= totalApps {
            // Find the last position in the target row
            let firstInRow = targetRow * appsPerRow
            let lastInRow = min(firstInRow + appsPerRow, totalApps) - 1
            targetIndex = lastInRow
        }
        
        print("   → Moving to: index=\(targetIndex), row=\(targetRow), col=\(currentCol)")
        return targetIndex
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
