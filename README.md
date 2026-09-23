# KajutaBot for iOS

Native iOS client for KajutaBot, built with SwiftUI. It lets you control the Discord music bot from an iPhone or iPad: browse the queue, skip tracks, manage favorites, search for music, switch Discord servers/voice channels, and receive live playback updates through SignalR.

## Requirements

- Xcode 26.2 or newer
- iOS / iPadOS 26.2 or newer
- A configured Discord application for OAuth login

## Build locally

1. Open `KajutaBot.xcodeproj` in Xcode.
2. Let Swift Package Manager resolve the project dependencies.
3. Select the **KajutaBot** target and configure **Signing & Capabilities** with your Apple development team.
4. In **Build Settings**, set:
   - `KAJUTABOT_DISCORD_CLIENT_ID` — your Discord application Client ID
   - `KAJUTABOT_API_BASE_URL` — optional; defaults to `https://api.kajuta.tryniecki.eu`
5. Add this redirect URI to your Discord application:
   ```
   discord-<CLIENT_ID>:/authorize/callback
   ```
6. Select an iPhone/iPad simulator or a connected device and press **Run** (`⌘R`).

No additional backend setup is required when using the default KajutaBot API.
