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
