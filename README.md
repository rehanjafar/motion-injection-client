# Mobile Ghost

Native, iPhone-only location simulation inspired by [Ghost Transit](https://github.com/rehanjafar/ghost-transit). Version **0.5.0 — editable schedules and random departure windows**.

Runs on the iPhone after initial setup; no always-connected Mac backend. **Developer Mode alone is not sufficient:** this implementation requires a device pairing file, LocalDevVPN, a mounted developer image, and a sideloaded/development-signed installation. Target device: **iPhone on iOS 26.5**. Deployment minimum is iOS 17.4; physical compatibility has not yet been verified for Mobile Ghost.

## Features

- Native SwiftUI / Apple Maps interface, map selection, search and coordinate entry.
- Fixed simulated locations and explicit restore through the real idevice developer-service bridge.
- Walking, driving and custom road-based bus routes with 2–12 stops.
- Adjustable 1–160 km/h speed; per-stop waits and departure speeds.
- Pause/resume and hold at destination; failed updates pause progress.
- Nearby mapped bus stops within 1 km, with explicit searches and a 30-second throttle.
- Saved places; persisted last acknowledged point for restore after relaunch.
- Multiple persisted departures within 30 days, with independent route/speed snapshots, estimated durations, overlap checks and a schedule list.
- OpenStreetMap walking map and pedestrian routing matching Ghost Transit, alongside Apple Maps and satellite views.
- Guided pairing, VPN, developer-image preparation and connection status.
- Background location execution for active routes and fixed-position refreshes, subject to iOS permission and scheduling.

## Setup on your iOS 26.5 iPhone

1. Keep Developer Mode enabled.
2. Obtain a pairing file **for this iPhone**, following the [StikDebug pairing guide](https://github.com/StikDebug/StikDebug-Guide/blob/main/pairing_file.md). A one-time computer step is acceptable; keep the file private.
3. Install [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044). Join a Wi-Fi network and connect LocalDevVPN.
4. Install Mobile Ghost using Xcode signing or sign its unsigned IPA with your sideloading tool. An unsigned IPA cannot be installed directly. Signing expiry depends on your signing method.
5. Open Mobile Ghost and import the pairing file. Allow local-network access. Let the developer image download and mount; use Connection → Prepare developer image / Retry if needed.
6. Select a nearby test point, press **Set location**, and check Apple Maps. Return to Mobile Ghost, press **Restore real location**, and check Maps again.
7. Allow location access when starting a session. Under Connection → Allow background location, request Always access; if iOS does not offer it immediately, use Open iPhone Settings. While Using can support a session started in the foreground with the location indicator visible, but does not grant unrestricted background execution.
8. Test a short route, switch to Maps, and then lock/unlock the phone. The app no longer intentionally pauses just because you leave it. Keep LocalDevVPN connected. Test your phone before relying on continued background movement.

## Build

First run `./scripts/fetch-device-library.sh` to download and verify the pinned device library. Then open `MobileGhost.xcodeproj` in Xcode, choose the MobileGhost target, and select your own development team under Signing & Capabilities. Choose a unique bundle identifier if your signing account requires one. Select your iPhone and Run. No developer team or signing credentials are included.

Unsigned device build:

```sh
xcodebuild -project MobileGhost.xcodeproj -scheme MobileGhost \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath .build/Device CODE_SIGNING_ALLOWED=NO build
```

Core checks (macOS with Swift installed):

```sh
./scripts/test-core.sh
```

The downloaded idevice static library is for physical iOS devices; this project does not claim Simulator support. Build validation used Xcode 27.1 and its iOS SDK, with a deployment minimum below iOS 26.5.

## Behavior and limitations

- **Active sessions attempt to continue in the background.** The app starts Core Location updates while in the foreground, declares the location background mode, and refreshes the simulated point while iOS allows execution. A system location indicator may appear and battery use increases. Denied/revoked permission prevents background refresh.
- **Fixed position:** it is actively refreshed in the background under the same conditions. If iOS suspends/terminates the app or the VPN fails, the last position may persist or revert. Fixed mode is not a guaranteed permanent location lock.
- **Do not force-quit.** Switching apps or locking the screen differs from swiping the app away. Force-quitting stops this app’s refresh loop.
- **Arm departures while in the foreground.** Arming starts the existing background location service and requires location permission, VPN and a mounted developer image. Leaving the app or locking the screen no longer cancels pending departures. This is best-effort execution, not an exact-time iOS wakeup guarantee; physical locked-screen testing remains required.
- An actual execution gap longer than three seconds pauses route movement rather than catching up; ordinary app switching does not itself pause it. Progress is committed only when the bridge accepts the location command.
- Starting a route moves to its first point. Setting a fixed location replaces the current route session; resume is then unavailable.
- Scheduled routes survive app restarts but restart disarmed. Re-arm explicitly after relaunch. Running routes become Interrupted; past departures become Missed. Restore disarms departures without deleting them. Manual location changes preserve pending schedules. A running or paused journey blocks another departure; a departure more than 60 seconds late is marked Missed, never replayed. Speed changes can extend a running route beyond its original estimated arrival and cause a later departure to be missed.
- Restore is explicit. After a restart, the app may briefly reapply the last stored point to reopen a developer session before clearing it. Errors leave the recovery record intact.
- Accepted commands do not establish what other apps display. Apps can detect software-simulated locations.
- This release is **not feature-complete with Ghost Transit**: mapped bus-service geometry/directions, GPX import/export, notifications and recurring schedules are not implemented. Bus mode uses automobile roads between selected stops; it is not a transit itinerary or bus-lane router.
- There is no App Store/TestFlight distribution or claim of support for every recent iOS release. Device pairing and VPN behavior can change across iOS versions.

## Privacy

No app accounts or analytics. Saved locations and the last acknowledged session point are stored locally in UserDefaults (not encrypted). Pairing records are managed by the inherited protected file store; do not commit or share them. MapKit sends place searches and Apple route coordinates to Apple. Selecting OpenStreetMap walking routes sends stop coordinates to routing.openstreetmap.de (FOSSGIS); its public service is throttled to at most one request per second. The Walking map requests visible tiles from tile.openstreetmap.org with HTTP caching. Displayed paths are mapped geometry, not a guarantee of public access or routing eligibility. No provider includes every walking path. Bus searches send the viewed centre to `overpass-api.de`; map/stop data © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright), ODbL. Developer image downloads use the inherited `doronz88/DeveloperDiskImage` GitHub source and require internet. Provider availability is not guaranteed.

## Origin and license

This is an independent derivative of **[TLocation](https://github.com/truongkma/t-location)** at commit `5e57f815e5958f133dfbaae8252473054adeccf0`, itself derived from **[StikDebug](https://github.com/StikDebug/StikDebug)** by Stephen Bove and contributors. Those projects supply pairing, tunneling, developer image mounting, and the idevice bridge. Mobile Ghost adds the native journey interface, route engine, scheduling and recovery controller. Modified October 22, 2026. Not an official upstream release.

**AGPL-3.0**, inherited unchanged; see [LICENSE](LICENSE). Copyright notices remain in inherited files. See [third-party notices](THIRD_PARTY_NOTICES.md) and [validation](docs/VALIDATION.md). Ghost Transit is the feature reference; its desktop code is not bundled.

## Background execution references

Apple documents the required background mode and active location service in [allowsBackgroundLocationUpdates](https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates) and [Handling location updates in the background](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background). These APIs permit background location processing; they do not guarantee uninterrupted developer-service simulation or survival after force-quit. Mobile Ghost background behavior remains unverified on a physical iOS 26.5 device.

## Updating an existing Xcode installation

Open the same project on the Mac, retain its existing bundle identifier and signing team, select your iPhone, then Run (Command–R). Do not delete MobileGhost. This installs the update over the existing app and renews its development signing as applicable. Xcode Personal Team installations still need periodic renewal; SideStore is optional and is not assumed to be installed.

## Locked-screen acceptance test (physical phone required)

1. Connect LocalDevVPN, open MobileGhost and confirm the connection is ready.
2. Save two short, nonoverlapping routes with departures a few minutes apart.
3. Open Schedules, tap Arm, and verify Background location active. Lock the phone before departure.
4. After both expected arrivals, unlock and check each schedule state and the simulated position. Repeat while switching apps and with a longer idle period.
5. Test VPN loss, revoked location permission, force-quit and relaunch. Departures must not overwrite a paused route or replay after the 60-second grace period. Re-arm after relaunch.

A simulator preview uses fake device connections and cannot validate location simulation, VPN behavior, signing, or locked-screen execution.

Weekly repeats and movement notifications: see [0.4.0 usage notes](docs/RECURRING-0.4.0.md).

Schedule editing and random windows: [0.5.0 usage notes](docs/SCHEDULE-EDITING-0.5.0.md).
