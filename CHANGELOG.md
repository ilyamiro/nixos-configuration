### 2.1.1

- feat/refactor: add a user widget and relocate sysinfo singletons
- fix: prevent location from auto-updating on re-boots or updates
- fix: fix inotifywait processes not being killed and being left as orphans
- style: change the toggle style in the launchertab
- feat: add a toggle to show the bar in the widget redactor
- fix: fix resize clamping bug in a widgetredactor
- fix: duplication bug in the wallpaperpicker
- style: change the cava template background color to surface
- i18n: add languages for the new capture setting
- feat(screenshot): optionally capture the region on mouse release (#239)
- style: make the visualizer widgets smoothly zero-out on the edges
- replace widget ipc calls with faster and immidiate singleton calls
- fix: fix jitter by removing continous background wifi-scanning
- feat: switch close-window keybind from Alt+f4 to Super + Q, and switch a music keybind to Super+M instead of Super + Q
- fix: a typo in matugen static config. Replace fastfetch with config
- feat: make the widgets in the redactor shrink if they become too big after rotation to prevent inaccassible states
- fix: fix the bug where the redactor toolbar for widgets wouldn't disappear
- fix: remove automatic network scanning to prevent jitter

### 2.1.0

- feat: add rotation iconbutton into the widget toolbar, allow to rotate widgets by 90 degrees
- feat: add a new visualizer widget
- fix: make sure the first launch applies the wallpaper through the wallpaper singleton
- fix: prevent crashes in the networkpopup widget. fixes #229
- feat: switch the wallpaperengine to use the singleton for communicating with the wallpaperpicker
- fix: battery widgets not following theme's borderradius
- style: make the draggable handle size bigger in the osd to match the syspanel
- feat: add a distinctPills setting for the solid and fill styles of the bar
- feat: optimize the opening sequence for the systempanel
- fix: make sure Main.qml specified the monitor the widget is open on
- feat/fix: add a distinctPills support for the topbar and sidebar, fix the topbar sliding out on all monitors when syspanel was open
- fix: make sure the visualizer widgets zero-out when nothing is playing
- feat: add a search animation for the clipboard
- feat: add a search animation for the launcher, add a center position
- i18n: add new keys for distinctPills setting for the bar and launcher center position
- style: implement a distinctPills property for pill-like look for all of the widgets. Change the paddings and adjust the sizes or all widgets for better look
- fix: eliminate the race condition of the displaywidgettab when only the last connected monitor was correctly reporting the existing desktop widgets
- feat: add Korean language support (#233)
- fix: show system monitor on the correct screen - #221
- style: increase the widget width and change alignment of icon glyps in the weatherfaceround
- style: change the harcoded JetBrains Font in dropdowns and switches to the fontfamily
- fix: prevent duplicate lockscreen cava subscriptions (#219)

### 2.0.7

- feat: a series of optimizations tied to visibility of widgets
- docs: add an update note. Solves #218
- fix: fix a duplication of modules bug
- make sure first launch correctly applies the wallpaper
- feat: a series of performance optimizations for components
- feat: make the first launch script a singleton instead
- fix a bug where location.sh was replaced by a single function
- i18n: add a missing translation for workspaces.desc
- feat: make the Sidebar able to change its height from the bartab settings like the topbar
- style: make the osd capslock, numlock and airplane mode display in the bottom center when the bar is on the side
- fix: clipboard search bar getting swallowed on the sides
- fix: make the order of calendar words depend on the language
- fix: change fullDate property to use toLocaleDateString (#214)
- fix: update targetMonthName formatting to use locale (#213)
- Fix installation script URL formatting in README (#215)
- fix: prevent niri workspaces variation from infinite looping

### 2.0.6-1

- Fix disc to desc typo and general improvements (#210)
- fix: delete lock and pid files for exiting
- fix: make bluelight enable correctly on startup
- feat: allow to shrink the topbar size up to 5%
- style: replace the on/off toggle in osd for capslock, numlock and airplane mode with a clickbutton, optimize it, and remove it for niri and sway
- fix: record selected monitor (#207)
- feat(osd): add CapsLock, NumLock and Airplane mode indicator support (#203)

### 2.0.6

- fix: make bluelight correctly and immidiatly follow the automated schedule. Add a city description
- add FUNDING.yml
- fix: blue_light_filter auto-location improved and fixed, also creating a flock for a single wl-gammarelay-rs instance
- feat(osd): add microphone OSD support and volume controls (#201)
- style: tune down the scale effect on hover for musicwdiget to prevent the thumbnail from sticking out on the left
- fix: loop property canExpand in quickshell
- style: change the volume of the whoosh sound in the MusicPopup equalizer
- feat: BlueLight singleton to ensure that bluelight applies on shell startup
- fix: stale thumbnails in the music player due to asynchronious loading
- fix: serpantinum --version flag to display version correctly on nix
- fix: make sure focus_daemon.py doesn't self-duplicate on reload and doesn't inflate the usage time
- feat: change the default icon in grouped notificatoins in the NotificationBox to use the icon of the grouped notifications that it contains
- fix(nix): add a ... to declare rev from flake.nix
- fix: return the expand functionality for the clipboard
- feat(i18n): add vietnamese translation
- fix: fix the FontAwesome icons being loaded in the widget redactor and making all of the icon glyps offset to the side
- fix: Weather location doesn't expire after 24h if manually set and doesn't get overwrriten on generaltab changes. fixes #195
- Fix switch.qml option text being outside of bounds on some translations
- docs: add autostart instructions for nix and the instructions on how to update for nixos
- fix(nix): make the version file help the Updater.qml display the correct version for about tab in the settings
- fix(i18n): fix the translation having a wrong key for widget tab
- fix: reroute lockscreen calls from systemctl to scripts that fix non-working buttons for niri or systems not on systemd
- nix: update the lockfile
- feat: add DDC brightness fallback (#193)

### 2.0.5

- fix: crucial bug where people couldn't use the config
- feat: make the musicpopup match the theme more by making the dim on the art in the background have the base theme color instead of black
- fix: make external kitty/fatfetch/cava configs not reinstall itself on update, and make location not re-evaluate itself on updates
- feat(i18n): add Armenian translation (#191)

### 2.0.4

- replace hardcoded delete buttons with a reusable
- Fix the calendar popup nodes having wrong scaling behavior breaking the 3d illusion
- feat: add a new reusable icon button instance for "delete button" implementation
- fix: prevent color theme reloads when the theme didn't actually change
- feat: add sub-nested tabs in the displaytab and split the widgets tab in the displaytab
- feat: make the launcher change its size based on the amount of elements and move the input to the bottom when attached to the bottom side of the screen
- feat: make the clipboard change its size based on the amount of elements and move the input to the bottom when attached to the bottom side of the screen
- docs: add a PR template
- Italian Translation fixes (#186)
- feat: make the Sddm theme have a better typing animation
- fix: remove sddm on-screen keyboard for some users
- fix: make config.sh not merge it on update

### 2.0.3

- fix: system options in the systempanel not being adapted to different init systems and different compositors
- feat: allow the launcher and the clipboard to close by clicking outside of their area- fix: make the draggable for changing sfx volume in the generaltab change the sound volume immidiatly on drag to allow the user to listen to how loud the sfx is directly
- Remove update notifications in the abouttab for nixos as redundant and disable updater singleton for nixos
- style: improve the appearing and disappearing animation for a volume/brightness osd when not attached to a bar)
- feat(notifications): add toggle for empty center graphic
- fix: make i18n fallback to english if a language misses a key, and only then fallback to a key
- feat(i18n): Add Italian localization
