Crowns of Caern
===============

An original dark-fantasy, turn-based strategy game.
Source code, manual and issue tracker:
https://github.com/CrownsofCaern/Crowns_of_Caern_4X

Starting the game
-----------------

Windows: run CrownsOfCaern.exe. Keep CrownsOfCaern.pck in the same folder.
  The game is not code-signed, so Windows SmartScreen may warn you. Choose
  "More info", then "Run anyway".

macOS: move "Crowns of Caern.app" to Applications and open it. The app is not
  notarized by Apple, so the first time macOS refuses to open it. Open
  System Settings > Privacy & Security and choose "Open Anyway", or run
  xattr -dr com.apple.quarantine "/Applications/Crowns of Caern.app"
  in Terminal.

Linux: run ./CrownsOfCaern.x86_64. Keep CrownsOfCaern.pck in the same folder.

Saves and settings are kept in the user data folder of "Crowns of Caern"
(Windows: %APPDATA%\Godot\app_userdata\Crowns of Caern, macOS:
~/Library/Application Support/Godot/app_userdata/Crowns of Caern, Linux:
~/.local/share/godot/app_userdata/Crowns of Caern).

Licences
--------

LICENSE                 the game's own licence (MIT)
CREDITS.md              fonts, textures, models and animation by third parties
THIRD_PARTY_NOTICES.txt the Godot Engine and the libraries built into it
licenses/               font licences (SIL Open Font License 1.1)
