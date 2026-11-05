# Build the Quest 3S test APK

This sandbox has no outbound network, so the three downloads below
must happen in your browser. Everything else is ready: the Godot
4.3 editor zip is already in Downloads, and `export_presets.cfg`
in this project already defines a **Quest 3S** preset (arm64,
OpenXR, debug-signed, passthrough + hand tracking from the
project's existing XR settings).

## 1. One-time setup (about 20 minutes)

1. **JDK 17**: install Microsoft Build of OpenJDK 17 (or Temurin 17).
   Verify in PowerShell: `java -version` shows 17.
2. **Godot editor**: unzip `Downloads/Godot_v4.3-stable_win64.exe.zip`
   anywhere and run it once.
3. **Export templates**: in the editor, Project → … actually:
   Editor → Manage Export Templates → Download and Install
   (fetches the official 4.3 templates).
4. **Android SDK**: install Android Studio (includes SDK + tools),
   or only its command-line tools. Then in the editor:
   Editor → Editor Settings → Export → Android, and set:
   - `Android Sdk Path` to your SDK (e.g.
     `C:\Users\<you>\AppData\Local\Android\Sdk`),
   - `Jdk Path` to your JDK 17.
5. Open this project (`project/project.godot`) in the editor once
   so it imports (wait until the import spinner stops).

## 2. Build the APK (about 2 minutes)

1. Project → Export… → select the **Quest 3S** preset.
2. Keystore: leave empty — Godot signs debug builds with its
   built-in debug key, which sideloads fine on your own headset.
3. Press **Export Project**, save as
   `project/exports/StarApp-Quest3S-debug.apk`.

Headless equivalent (same machine, after setup):
`Godot_v4.3-stable_win64_console.exe --headless --path project --export-debug "Quest 3S" project/exports/StarApp-Quest3S-debug.apk`

## 3. Install on the Quest 3S

1. On the headset: enable **Developer Mode** (Meta Horizon phone
   app → Devices → Headset settings → Developer mode).
2. Connect the headset by USB, accept the RSA prompt inside VR.
3. Install with the platform tools already in Downloads
   (`platform-tools-latest-windows.zip` → unzip → in that folder):
   `.\adb.exe install -r StarApp-Quest3S-debug.apk`
   or drop the APK into SideQuest / Meta Quest Developer Hub.
4. Launch **Star App** from Unknown Sources in the headset library.

## 4. What to check in-headset (report back)

- Room visible at boot (passthrough), panel readable upper-right.
- Pinch Moon/planet once outdoors: sky locks, confirmation shows.
- Pinch Saturn: orange glow on, hologram beside it, Saturn line speaks.
- New pinch elsewhere: old voice stops, highlight moves or clears.
- Telescope (2nd pinch): huge close planet, dial drags 1x–10x.
- Travel (3rd pinch): Mars real panorama; others simulated shells
  with decks/aurorae on gas giants; 4th pinch returns to room.
- Hands: rainbow rim outline tracing your real hands; pinch a room
  planet, hold, and carry it — release drops it back to its anchor.
