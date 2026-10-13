# Offline Mesh (Android)

Hotspot-based chat and file sharing. No internet, no servers. One phone hosts a Wi-Fi hotspot, the other scans its QR code to join.

## Set up the project

This folder holds the source files. The Gradle wrapper and icons come from `flutter create`:

```bash
flutter create --org com.example --project-name offline_mesh --platforms=android offline_mesh_app
cd offline_mesh_app

# Overlay these files (replace when asked):
#   pubspec.yaml
#   lib/                                   (main.dart, session.dart, lan_node.dart, hotspot_service.dart, screens/)
#   android/app/src/main/AndroidManifest.xml
#   android/app/src/main/kotlin/com/example/offline_mesh/MainActivity.kt

flutter pub get
```

**Set `minSdk` to 29** (needed for `WifiNetworkSpecifier`). In `android/app/build.gradle.kts`:

```kotlin
minSdk = 29
```
(or `minSdkVersion 29` in `build.gradle` on older templates)

Run on **two physical Android phones** (emulators can't create a hotspot):

```bash
flutter run -d <phone-id>
```

## Using it

1. Phone A: **Host a network**. Grant Location / Nearby devices. Location (GPS) must be switched on.
2. Phone B: **Join a network** and scan the QR. Approve the Android "connect to device" prompt.
3. Chat and use the paperclip to send files. On the receiving phone, tap **Download**, then **Open**.

Received files land in the app's external files folder (`Android/data/com.example.offline_mesh/files/received`).

## Known limitations

- **Hotspot credentials are chosen by Android** (`LocalOnlyHotspot` can't set a custom SSID or password), hence the QR code.
- If hosting fails, switch off the phone's normal hotspot/tethering and Wi-Fi Direct, then retry. Some OEMs also block `LocalOnlyHotspot`.
- **The app must stay in the foreground.** Android may stop the hotspot or sockets in the background. A foreground service is the next step to fix this.
- The Host is the hub: all traffic goes through it, and files are stored on the Host.
- `file_picker` copies the chosen file to app cache before sending, which is slow for multi-GB files.
- Leaving the chat screen as a client ends the session (no confirmation dialog yet).
