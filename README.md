# MacWinTil

*A lightweight, native macOS tiling window manager built with Swift**

> [!TIP] 
> **Why MacWinTil?**
>
> - Most macOS "tiling" managers are just basic window positioning tools
> - Existing solutions lack visual indicators and proper workspace management
> - Built natively in Swift for optimal macOS integration and performance
> - Designed to be lightweight yet feature-rich

## ✨ Features

### 🪟 **Smart Tiling Layouts**

- **Adaptive layouts**: Automatically arranges windows based on count
  - 1 window: Full screen
  - 2 windows: Side-by-side split
  - 3 windows: Left half + right half split vertically
  - 4 windows: Perfect quadrant grid
  - 5+ windows: Dynamic grid layout


> [!WARNING] 
> ### 🏠 **Virtual Spaces 
> **(still buggy and WIP)**

- Create unlimited virtual workspaces for different projects
- Visual menubar indicators (●○○) showing current and available spaces
- Persistent spaces that survive system sleep/wake cycles
- Quick space switching with customizable shortcuts

### ⌨️ **Vim-Style Edit Mode**

- **Toggle edit mode** to instantly rearrange windows
- **hjkl navigation**: Move windows with familiar vim keys
- **Live exclusion**: Press 'e' to exclude/include apps from tiling
- **Visual feedback**: Menubar turns blue when in edit mode

### ⚙️ **Smart Configuration**

- **Auto-generated config** at `~/.config/MacWinTil/config.json`
- **App exclusion**: Exclude specific apps from tiling (Finder, Xcode, etc.)
- **Custom shortcuts**: Fully customizable keyboard shortcuts
- **Detailed documentation**: Auto-generated README in config directory

### 🎯 **Intelligent Menubar**

- **Space indicators**: Visual dots showing all spaces and current selection
- **App overview**: See which apps are in each space
- **Quick actions**: Create spaces, switch spaces, manage apps
- **Edit mode indicator**: Blue text when in edit mode

## 🛠 Installation

1. **Clone the repository**

   ```bash
   git clone https://github.com/LuComic/MacWinTil.git
   ```

2. **Build in Xcode**

   - Open the project in Xcode
   - Build and run the project in there, or Product -> Archive to make it into an application

3. **Grant permissions**
   - Go to **System Preferences** → **Privacy & Security** → **Accessibility**
   - Add MacWinTil to the allowed apps

## ⌨️ Default Shortcuts

| Action                | Shortcut | Description                             |
| --------------------- | -------- | --------------------------------------- |
| **Space Management**  |          |                                         | 
| Create New Space      | `⇧⌘⌥N`   | Create a new virtual workspace          |
| Close Space           | `⇧⌘⌥W`   | Close current space                     |
| Switch to Space 1-5   | `⌘⌥1-5`  | Quick switch to specific spaces         |
| **Window Management** |          |                                         |
| Enter Edit Mode       | `⇧⌘⌥E`   | Toggle vim-style window editing         |
| **Edit Mode Keys**    |          |                                         |
| Move Left             | `h`      | Swap window with left neighbor          |
| Move Down             | `j`      | Swap window with below neighbor         |
| Move Up               | `k`      | Swap window with above neighbor         |
| Move Right            | `l`      | Swap window with right neighbor         |
| Toggle Exclusion      | `e`      | Include/exclude current app from tiling |

## 📁 Configuration

MacWinTil automatically creates a configuration directory at `~/.config/MacWinTil/` containing:

- **`config.json`**: Main configuration file
- **`spaces.json`**: Persistent space data (works by itself, do not change)
- **`README.md`**: Detailed configuration guide

### Example Config

```json
{
  "excludedApps": ["Finder", "Xcode", "Terminal", "Activity Monitor"],
  "shortcuts": {
    "createNewSpace": "⇧⌘⌥N",
    "enterEditMode": "⇧⌘⌥E",
    "switchToSpace1": "⌘⌥1"
  }
}
```

## 🎮 Usage

1. **Launch MacWinTil** - Look for the space indicator in your menubar ⚪️
2. **Open some apps** - They'll automatically tile in the current space, if not excluded
3. **Create spaces** - Use `⇧⌘⌥N` to create workspaces for different projects
4. **Enter edit mode** - Press `⇧⌘⌥E` and use `hjkl` to rearrange windows
5. **Exclude apps** - In edit mode, press `e` to toggle app exclusion

## 🏗 Architecture

MacWinTil is built with a clean, modular architecture:

- **WindowManager**: Core tiling logic and space management
- **TilingLayout**: Smart layout calculations for different window counts
- **ConfigManager**: Configuration handling with auto-generation
- **MenuBarManager**: Interactive menubar with visual indicators
- **KeyboardShortcutsManager**: Customizable shortcut handling
- **StartupManager**: Clean initialization and permission handling
