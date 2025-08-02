//
//  KeyboardShortcutsManager.swift
//  MacWinTil
//
//  Created by Lukas Jääger on 02.08.2025.
//

import Foundation
import AppKit
import KeyboardShortcuts

// Dynamic keyboard shortcut names - will be created based on config
extension KeyboardShortcuts.Name {
    static let createNewSpace = Self("createNewSpace")
    static let closeSpace = Self("closeSpace")
    static let switchToSpace1 = Self("switchToSpace1")
    static let switchToSpace2 = Self("switchToSpace2")
    static let switchToSpace3 = Self("switchToSpace3")
    static let switchToSpace4 = Self("switchToSpace4")
    static let switchToSpace5 = Self("switchToSpace5")
    static let toggleAppExclusion = Self("toggleAppExclusion")
}

class KeyboardShortcutsManager {
    private var windowManager: WindowManager
    private let configManager = ConfigManager.shared
    
    init(windowManager: WindowManager) {
        self.windowManager = windowManager
        setupKeyboardShortcuts()
    }
    
    private func setupKeyboardShortcuts() {
        let shortcuts = configManager.config.shortcuts
        
        // Set up shortcuts based on config
        setupShortcut(for: .createNewSpace, configKey: "createNewSpace", shortcuts: shortcuts) { [weak self] in
            self?.windowManager.createNewSpace()
        }
        
        setupShortcut(for: .closeSpace, configKey: "closeSpace", shortcuts: shortcuts) { [weak self] in
            self?.windowManager.closeCurrentSpace()
        }
        
        setupShortcut(for: .switchToSpace1, configKey: "switchToSpace1", shortcuts: shortcuts) { [weak self] in
            self?.windowManager.switchToSpace(1)
        }
        
        setupShortcut(for: .switchToSpace2, configKey: "switchToSpace2", shortcuts: shortcuts) { [weak self] in
            self?.windowManager.switchToSpace(2)
        }
        
        setupShortcut(for: .switchToSpace3, configKey: "switchToSpace3", shortcuts: shortcuts) { [weak self] in
            self?.windowManager.switchToSpace(3)
        }
        
        setupShortcut(for: .switchToSpace4, configKey: "switchToSpace4", shortcuts: shortcuts) { [weak self] in
            self?.windowManager.switchToSpace(4)
        }
        
        setupShortcut(for: .switchToSpace5, configKey: "switchToSpace5", shortcuts: shortcuts) { [weak self] in
            self?.windowManager.switchToSpace(5)
        }
        
        setupShortcut(for: .toggleAppExclusion, configKey: "toggleAppExclusion", shortcuts: shortcuts) { [weak self] in
            self?.windowManager.toggleCurrentAppExclusion()
        }
    }
    
    private func setupShortcut(for shortcutName: KeyboardShortcuts.Name, configKey: String, shortcuts: [String: String], action: @escaping () -> Void) {
        guard let shortcutString = shortcuts[configKey] else {
            print("⚠️ No shortcut found for \(configKey)")
            return
        }
        
        if let shortcut = parseShortcutString(shortcutString) {
            // Set the shortcut programmatically
            KeyboardShortcuts.setShortcut(shortcut, for: shortcutName)
            
            // Set up the action
            KeyboardShortcuts.onKeyUp(for: shortcutName, action: action)
            
            print("✅ Set up shortcut \(configKey): \(shortcutString)")
        } else {
            print("❌ Failed to parse shortcut for \(configKey): \(shortcutString)")
        }
    }
    
    private func parseShortcutString(_ shortcutString: String) -> KeyboardShortcuts.Shortcut? {
        // Parse shortcut strings like "⌘⌥1" or "⇧⌘⌥N"
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
        
        guard let key = keyChar else {
            print("❌ No key found in shortcut string: \(shortcutString)")
            return nil
        }
        
        // Convert character to KeyEquivalent
        let keyEquivalent = getKeyEquivalent(for: key)
        guard let keyEq = keyEquivalent else {
            print("❌ Unsupported key: \(key)")
            return nil
        }
        
        return KeyboardShortcuts.Shortcut(keyEq, modifiers: modifiers)
    }
    
    private func getKeyEquivalent(for char: Character) -> KeyboardShortcuts.Key? {
        switch char.lowercased() {
        case "a": return .a
        case "b": return .b
        case "c": return .c
        case "d": return .d
        case "e": return .e
        case "f": return .f
        case "g": return .g
        case "h": return .h
        case "i": return .i
        case "j": return .j
        case "k": return .k
        case "l": return .l
        case "m": return .m
        case "n": return .n
        case "o": return .o
        case "p": return .p
        case "q": return .q
        case "r": return .r
        case "s": return .s
        case "t": return .t
        case "u": return .u
        case "v": return .v
        case "w": return .w
        case "x": return .x
        case "y": return .y
        case "z": return .z
        case "1": return .one
        case "2": return .two
        case "3": return .three
        case "4": return .four
        case "5": return .five
        case "6": return .six
        case "7": return .seven
        case "8": return .eight
        case "9": return .nine
        case "0": return .zero
        default: return nil
        }
    }
}
