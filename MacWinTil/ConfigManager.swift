//
//  ConfigManager.swift
//  MacWinTil
//
//  Created by Lukas Jääger on 02.08.2025.
//

import Foundation

struct MacWinTilConfig: Codable {
    var excludedApps: [String]
    var shortcuts: [String: String]
    var version: String
    
    static let defaultConfig = MacWinTilConfig(
        excludedApps: [
            "Finder",
            "Xcode",
            "Terminal",
            "Activity Monitor"
        ],
        shortcuts: [
            "createNewSpace": "⇧⌘⌥N",
            "closeSpace": "⇧⌘⌥W",
            "switchToSpace1": "⌘⌥1",
            "switchToSpace2": "⌘⌥2",
            "switchToSpace3": "⌘⌥3",
            "switchToSpace4": "⌘⌥4",
            "switchToSpace5": "⌘⌥5",
            "toggleAppExclusion": "⇧⌘⌥E",
            "newWindowShortcut": "⌘N"
        ],
        version: "1.0"
    )
}

class ConfigManager {
    static let shared = ConfigManager()
    
    private let configDirectoryPath: String
    private let configFilePath: String
    
    private(set) var config: MacWinTilConfig
    
    private init() {
        // Create config directory path: ~/.config/MacWinTil/
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        configDirectoryPath = homeDirectory.appendingPathComponent(".config/MacWinTil").path
        configFilePath = configDirectoryPath + "/config.json"
        
        // Load or create config
        config = Self.loadOrCreateConfig(at: configFilePath, in: configDirectoryPath)
    }
    
    private static func loadOrCreateConfig(at filePath: String, in directoryPath: String) -> MacWinTilConfig {
        let fileManager = FileManager.default
        
        // Check if config file exists
        if fileManager.fileExists(atPath: filePath) {
            // Try to load existing config
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
                let config = try JSONDecoder().decode(MacWinTilConfig.self, from: data)
                print("✅ Loaded existing config from: \(filePath)")
                return config
            } catch {
                print("⚠️ Error loading config file, using defaults: \(error)")
                // If loading fails, create new config with defaults
                return createDefaultConfig(at: filePath, in: directoryPath)
            }
        } else {
            // Config doesn't exist, create it
            print("📝 Config file not found, creating default config at: \(filePath)")
            return createDefaultConfig(at: filePath, in: directoryPath)
        }
    }
    
    private static func createDefaultConfig(at filePath: String, in directoryPath: String) -> MacWinTilConfig {
        let fileManager = FileManager.default
        let config = MacWinTilConfig.defaultConfig
        
        do {
            // Create config directory if it doesn't exist
            try fileManager.createDirectory(atPath: directoryPath, withIntermediateDirectories: true, attributes: nil)
            
            // Encode and save config
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(config)
            try data.write(to: URL(fileURLWithPath: filePath))
            
            print("✅ Created default config file at: \(filePath)")
            
            // Also create a README file to help users understand the config
            createConfigReadme(in: directoryPath)
            
            return config
        } catch {
            print("❌ Error creating config file: \(error)")
            return config
        }
    }
    
    private static func createConfigReadme(in directoryPath: String) {
        let readmePath = directoryPath + "/README.md"
        let readmeContent = """
# MacWinTil Configuration

This directory contains configuration files for MacWinTil, a macOS tiling window manager.

## config.json

### Excluded Apps
Add app names to the `excludedApps` array to prevent them from being managed by the tiling system:

```json
"excludedApps": [
    "Finder",
    "Xcode",
    "Terminal",
    "Activity Monitor",
    "Your App Name Here"
]
```

**Note**: Use the exact app name as it appears in the Applications folder or Activity Monitor.

### Keyboard Shortcuts
Customize keyboard shortcuts in the `shortcuts` object:

```json
"shortcuts": {
    "createNewSpace": "⇧⌘⌥N",
    "closeSpace": "⇧⌘⌥W",
    "switchToSpace1": "⌘⌥1",
    "switchToSpace2": "⌘⌥2",
    "switchToSpace3": "⌘⌥3",
    "switchToSpace4": "⌘⌥4",
    "switchToSpace5": "⌘⌥5",
    "toggleAppExclusion": "⇧⌘⌥E",
    "newWindowShortcut": "⌘N"
}
```

**Shortcut Format**: Use ⌘ (Command), ⌥ (Option), ⌃ (Control), ⇧ (Shift) followed by a key.

### Default Shortcuts
- **⇧⌘⌥N** - Create new space
- **⇧⌘⌥W** - Close current space  
- **⌘⌥1-5** - Switch to space 1-5
- **⇧⌘⌥E** - Toggle exclusion of currently active app from tiling
- **⌘N** - New window shortcut (used when creating windows in spaces)

### Dynamic App Exclusion
You can exclude/include apps from tiling without editing the config:
1. Focus the app you want to exclude/include
2. Press **⇧⌘⌥E** to toggle its exclusion status
3. The change is automatically saved to the config file

### Applying Changes
After modifying the config file, restart MacWinTil for changes to take effect.

---
Generated by MacWinTil v1.0
"""
        
        do {
            try readmeContent.write(toFile: readmePath, atomically: true, encoding: .utf8)
            print("📖 Created README.md at: \(readmePath)")
        } catch {
            print("⚠️ Could not create README.md: \(error)")
        }
    }
    
    // MARK: - Private Methods
    
    private func saveConfig() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(config)
            try data.write(to: URL(fileURLWithPath: configFilePath))
            print("💾 Config saved successfully")
        } catch {
            print("❌ Error saving config: \(error)")
        }
    }
    
    // MARK: - Public Methods
    
    func isAppExcluded(_ appName: String) -> Bool {
        return config.excludedApps.contains(appName)
    }
    
    func addExcludedApp(_ appName: String) {
        if !config.excludedApps.contains(appName) {
            config.excludedApps.append(appName)
            saveConfig()
            print("✅ Added \(appName) to excluded apps")
        }
    }
    
    func removeExcludedApp(_ appName: String) {
        if let index = config.excludedApps.firstIndex(of: appName) {
            config.excludedApps.remove(at: index)
            saveConfig()
            print("✅ Removed \(appName) from excluded apps")
        }
    }
    
    func getShortcut(for action: String) -> String? {
        return config.shortcuts[action]
    }
    
    func reloadConfig() {
        config = Self.loadOrCreateConfig(at: configFilePath, in: configDirectoryPath)
        print("🔄 Config reloaded")
    }
    
    func printConfigInfo() {
        print("📋 MacWinTil Configuration:")
        print("   Config file: \(configFilePath)")
        print("   Excluded apps: \(config.excludedApps.joined(separator: ", "))")
        print("   Shortcuts: \(config.shortcuts.count) configured")
    }
}
