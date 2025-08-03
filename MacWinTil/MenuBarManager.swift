//
//  MenuBarManager.swift
//  MacWinTil
//
//  Created by Lukas Jääger on 02.08.2025.
//

import Foundation
import AppKit
import SwiftUI

class MenuBarManager: ObservableObject {
    private var statusItem: NSStatusItem?
    private var windowManager: WindowManager
    
    init(windowManager: WindowManager) {
        self.windowManager = windowManager
        setupMenuBar()
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            updateMenuBarTitle()
            button.action = #selector(menuBarClicked)
            button.target = self
        }
        
        // Update menubar when spaces change
        windowManager.$currentSpace.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateMenuBarTitle()
            }
        }.store(in: &cancellables)
        
        windowManager.$spaces.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateMenuBarTitle()
            }
        }.store(in: &cancellables)
        
        // Update menubar when edit mode changes
        windowManager.$isEditMode.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateMenuBarTitle()
            }
        }.store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private func updateMenuBarTitle() {
        // Get all space numbers and show as filled/unfilled circles
        let sortedSpaces = windowManager.spaces.keys.sorted()
        let currentSpace = windowManager.currentSpace
        let isEditMode = windowManager.isEditMode
        
        var circles: [String] = []
        
        for spaceNumber in sortedSpaces {
            if spaceNumber == currentSpace {
                circles.append("●") // Filled circle for current space
            } else {
                circles.append("○") // Empty circle for other spaces
            }
        }
        
        let title = circles.joined(separator: " ")
        
        if let button = statusItem?.button {
            if isEditMode {
                // Create attributed string with light blue color for edit mode
                let attributedTitle = NSAttributedString(
                    string: title,
                    attributes: [.foregroundColor: NSColor.systemBlue]
                )
                button.attributedTitle = attributedTitle
            } else {
                // Normal white/system color
                button.attributedTitle = NSAttributedString(
                    string: title,
                    attributes: [.foregroundColor: NSColor.controlTextColor]
                )
            }
        }
    }
    
    @objc private func menuBarClicked() {
        let menu = NSMenu()
        
        let currentApps = windowManager.spaces[windowManager.currentSpace, default: []]
        if !currentApps.isEmpty {
            let appsItem = NSMenuItem(title: "Apps: \(currentApps.joined(separator: ", "))", action: nil, keyEquivalent: "")
            appsItem.isEnabled = false
            menu.addItem(appsItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Space management
        let createSpaceShortcut = ConfigManager.shared.getShortcut(for: "createNewSpace") ?? "⌘⌥N"
        let (keyEquivalent, modifierMask) = parseShortcutForMenu(createSpaceShortcut)
        let newSpaceItem = NSMenuItem(title: "Create New Space", action: #selector(createNewSpace), keyEquivalent: keyEquivalent)
        newSpaceItem.keyEquivalentModifierMask = modifierMask
        newSpaceItem.target = self
        menu.addItem(newSpaceItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // List all spaces
        let sortedSpaces = windowManager.spaces.keys.sorted()
        for spaceNumber in sortedSpaces {
            let apps = windowManager.spaces[spaceNumber, default: []]
            let isCurrentSpace = spaceNumber == windowManager.currentSpace
            let title = isCurrentSpace ? "● Space \(spaceNumber) (\(apps.count))" : "○ Space \(spaceNumber) (\(apps.count))"
            
            let spaceItem = NSMenuItem(title: title, action: #selector(switchToSpace(_:)), keyEquivalent: "")
            spaceItem.target = self
            spaceItem.tag = spaceNumber
            menu.addItem(spaceItem)
            
            // Show apps in this space
            if !apps.isEmpty {
                for app in apps {
                    let appItem = NSMenuItem(title: "  • \(app)", action: #selector(removeApp(_:)), keyEquivalent: "")
                    appItem.target = self
                    appItem.representedObject = ["space": spaceNumber, "app": app]
                    menu.addItem(appItem)
                }
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit option
        let quitItem = NSMenuItem(title: "Quit MacWinTil", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }
    
    @objc private func createNewSpace() {
        windowManager.createNewSpace()
    }
    
    @objc private func switchToSpace(_ sender: NSMenuItem) {
        windowManager.switchToSpace(sender.tag)
    }
    
    @objc private func removeApp(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: Any],
              let spaceNumber = info["space"] as? Int,
              let appName = info["app"] as? String else { return }
        
        if spaceNumber == windowManager.currentSpace {
            windowManager.removeAppFromCurrentSpace(appName)
        }
    }
    
    // MARK: - Helper Methods
    private func parseShortcutForMenu(_ shortcutString: String) -> (keyEquivalent: String, modifierMask: NSEvent.ModifierFlags) {
        var modifiers: NSEvent.ModifierFlags = []
        var keyChar: Character?
        
        for char in shortcutString {
            switch char {
            case "⌘": // Command
                modifiers.insert(.command)
            case "⌥": // Option
                modifiers.insert(.option)
            case "⇧": // Shift
                modifiers.insert(.shift)
            case "⌃": // Control
                modifiers.insert(.control)
            default:
                keyChar = char
            }
        }
        
        let key = keyChar?.lowercased() ?? "n"
        return (keyEquivalent: String(key), modifierMask: modifiers)
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// Need to import Combine for the sink operations
import Combine
