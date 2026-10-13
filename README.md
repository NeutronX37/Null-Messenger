# Null Messenger

Chat and share files between Android phones with **no internet, no mobile data and no servers**. One phone creates a local Wi-Fi hotspot, the others join it, and everything travels directly between the devices.

## Features

- **Host or join:** one tap to host a network, or scan a QR code to join one
- **Text chat** between all connected phones
- **File transfer** of any type and size, streamed with a progress bar
- **Fully offline:** works with no SIM, no Wi-Fi router and no internet
- **Manual join:** type the network name and password if the camera scanner isn't working

## How it works

```
 Host phone                       Client phones
 ┌───────────────────┐            ┌───────────────────┐
 │ Local-only hotspot│◄── Wi-Fi ──│ Join hotspot      │
 │ WebSocket hub /ws │◄─ socket ──│ WebSocket client  │
 │ File store /file  │◄── HTTP ───│ Upload / download │
 └───────────────────┘            └───────────────────┘
```

1. **Host** starts an Android *local-only hotspot*. Android picks the network name and password, and the app shows them as a QR code.
2. **Client** scans the QR code (or types the details) and joins that Wi-Fi network. Android shows a one-time approval prompt.
3. The client connects to the host (the Wi-Fi gateway address) over a **WebSocket** for chat. If that fails, it listens for the host's UDP broadcast to find it.
4. **Files** are uploaded to the host over HTTP and announced to everyone. Other phones tap **Download** to fetch them.

The host acts as the hub: all messages and files pass through it, and files are stored on the host phone.

## Requirements

- Android 10 or newer (API 29+), a real phone (emulators can't create hotspots)
- Two or more phones with Wi-Fi
- Permissions the app asks for: Location, Nearby devices (Android 13+), Camera (QR scanning)

## Using the app

**On the host phone**
1. Turn on Location (GPS) in quick settings.
2. Open Null Messenger and tap **Host a network**. Allow the permissions.
3. A QR code appears. Tap **Open chat** to start.

**On every other phone**
1. Tap **Join a network** and scan the host's QR code. If the camera doesn't work, tap the keyboard icon and enter the network name and password shown on the host's screen.
2. Approve the Android prompt to connect to the device.
3. Chat, and use the paperclip to send files. Tap **Download** on a received file, then **Open**.

Received files are saved in the app's external files folder: `Android/data/com.example.offline_mesh/files/received`.

## Building the APK (no setup on your computer)

The APK is built in the cloud with GitHub Actions.

1. Put the project files in a GitHub repository.
2. Add the workflow file `.github/workflows/build.yml`. It creates a fresh Flutter project, copies the source files into the right folders, forces the Android build settings the libraries need (minimum Android 10, compile against API 36) and runs `flutter build apk --release --no-shrink`.
3. Open the **Actions** tab, run the workflow, and download **offline-mesh-apk** from **Artifacts**.
4. Unzip it and install `app-release.apk` on each phone.

> Every build is signed with a new debug key. **Uninstall the old version before installing a new build**, or Android will refuse the update.

## Source files

| File | Purpose |
|---|---|
| `pubspec.yaml` | Dependencies |
| `lib/main.dart` | App entry and home screen |
| `lib/session.dart` | Chat state, sending and receiving messages and files |
| `lib/lan_node.dart` | Host server, client, and UDP discovery |
| `lib/hotspot_service.dart` | Dart side of the hotspot and Wi-Fi bridge, permissions |
| `lib/screens/host_screen.dart` | Hotspot start and QR display |
| `lib/screens/join_screen.dart` | QR scanner, manual entry, joining |
| `lib/screens/chat_screen.dart` | Chat and file UI |
| `android/.../AndroidManifest.xml` | Permissions and app name |
| `android/.../MainActivity.kt` | Android native code: hotspot, Wi-Fi join, multicast lock |

## Tech stack

Flutter (Dart) with a native Kotlin bridge. Networking uses only Dart's built-in `dart:io` sockets (WebSocket, HTTP, UDP). Packages: `permission_handler`, `qr_flutter`, `mobile_scanner`, `file_picker`, `path_provider`, `open_filex`.

## Known limitations

- **Android chooses the hotspot name and password**, which is why QR codes (or manual entry) are needed.
- Some phone makers block local-only hotspots. If hosting fails, turn off the normal hotspot and Wi-Fi Direct, and make sure Location is on.
- **Keep the app open.** Android can stop the hotspot and connections when the app is in the background. A foreground service is the planned fix.
- Messages are not saved after the chat closes, and there is no encryption beyond the hotspot's own Wi-Fi password.
- Choosing very large files copies them to temporary storage first, which can be slow.

## Troubleshooting

| Problem | Try this |
|---|---|
| Host fails to start | Turn on Location, allow all permissions, turn off normal hotspot and Wi-Fi Direct, retry |
| Camera shows an error | Allow Camera in app settings, or use the keyboard icon to enter the network manually |
| "App not installed" | Uninstall the old version first |
| Can't connect after joining | Make sure the host's app is open in the foreground; move the phones closer |

## Roadmap

- Foreground service so chats survive in the background
- Copy/paste connection code as a camera-free alternative
- Message history and delivery status
- Optional end-to-end encryption
