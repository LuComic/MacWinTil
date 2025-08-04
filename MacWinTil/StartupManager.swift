//
//  StartupManager.swift
//  MacWinTil
//
//  Created by Lukas Jääger on 02.08.2025.
//

import Foundation
import AppKit

class StartupManager {
    
    static func checkAndPromptForCleanStart(completion: @escaping (Bool) -> Void) {
        let runningApps = NSWorkspace.shared.runningApplications.filter { app in
            // Filter out system apps and our own app
            guard let bundleId = app.bundleIdentifier,
                  let appName = app.localizedName else { return false }
            
            // Skip system apps, Finder, and our own app
            let systemApps = [
                "com.apple.finder",
                "com.apple.dock",
                "com.apple.systemuiserver",
                "com.apple.controlcenter",
                "com.apple.notificationcenterui",
                "com.apple.spotlight",
                "com.apple.loginwindow",
                "com.apple.MacWinTil"
            ]
            
            // Skip apps excluded in config
            if ConfigManager.shared.isAppExcluded(appName) {
                return false
            }
            
            return !systemApps.contains(bundleId) && 
                   !bundleId.hasPrefix("com.apple.") &&
                   appName != "MacWinTil" &&
                   app.activationPolicy == .regular
        }
        
        if runningApps.isEmpty {
            completion(true)
            return
        }
        
        let alert = NSAlert()
        alert.messageText = "MacWinTil Setup"
        alert.informativeText = """
        MacWinTil works best with a clean desktop. 
        
        Currently running applications:
        \(runningApps.compactMap { $0.localizedName }.joined(separator: ", "))
        
        Would you like to close all applications to start fresh? This will help MacWinTil manage your windows properly.
        """
        alert.addButton(withTitle: "Close All & Start Fresh")
        alert.addButton(withTitle: "Continue Anyway")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn: // Close All & Start Fresh
            closeAllApplications(runningApps) {
                completion(true)
            }
        case .alertSecondButtonReturn: // Continue Anyway
            completion(true)
        default: // Cancel
            completion(false)
        }
    }
    
    private static func closeAllApplications(_ apps: [NSRunningApplication], completion: @escaping () -> Void) {
        let group = DispatchGroup()
        
        for app in apps {
            group.enter()
            
            // Try graceful termination first
            app.terminate()
            
            // Give it a moment to close gracefully
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if app.isTerminated {
                    group.leave()
                } else {
                    // Force quit if still running
                    app.forceTerminate()
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            // Wait a bit more for everything to settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                completion()
            }
        }
    }
}
