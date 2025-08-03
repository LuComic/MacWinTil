# MacWinTil

> [!TIP]
>
> ### Why?
>
> - Not many tiling window managers for mac, mostly just window managers (eg window to the left side, center etc)
> - The ones there are, are often bloated and miss features (like the indicator 1, 2, 3 that you can get with Waybar or something)
> - (Want to do something with python and library PyXA, which helps Python talk to the Mac, seems interesting.)
> - Since I couldn't get the python package working, I'm going to do this using Swift

## Usage

- Have a mac
- Install and build the app in Xcode
- You might have to give it access for Accessibility under Privacy & Security

## Features

- A tiling window manager, so opens apps in a spiral
- A config file, to exclude apps from tiling and edit shortcuts
- Edit mode, which lets you move the windows around and include/exclude them instantly
- Spaces (don't really work rn and are buggy)


 ## Config usage

 - On the first run the application creates a config file at ~/.config/MacWinTil/config.json.
 - You can costumize apps to be excluded from tiling and keyboard shortcuts in the config file. Better instructions will be generated into a README file under the config.
