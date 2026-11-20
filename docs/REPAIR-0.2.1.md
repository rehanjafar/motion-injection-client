# MobileGhost 0.2.1 — map interaction and signing repair

## Install over the current app

Open your existing project at:
`/Users/rehanjafar/Documents/Codex/2026-10-22/i-want-to-recreate-the-spoofer/outputs/mobile-ghost/MobileGhost.xcodeproj`

Connect your iPhone, select it in Xcode, and press Command–R. Keep the same team and bundle identifier. Do not delete MobileGhost. Confirm version 0.2.1 in Library.

## Repairs

- Removed full-map control overlays. Header, search and map controls occupy separate layout areas.
- Explicitly enabled all native map interactions and made pin selection a simultaneous spatial tap gesture.
- Disconnected developer services no longer disable map browsing; an explicit Setup banner replaces the blocking connection overlay. The expiry modal still blocks until dismissed.
- Developer-image preflight checks now run on a background thread. Previously they could block the main thread while waiting on the device.
- Mount-status polling is bounded to one outstanding check and avoids active location sessions.
- Pairing-file preparation moved off the UI thread for simulation commands.
- Replaced the unavailable bookmark icon.
- A new Xcode-installed profile can advance the cached expiry without overwriting newer SideStore refresh dates with old embedded dates.

## Signing

The prior 0.2.0 build reused the profile created October 22 and expiring October 29 at 12:28 p.m. Toronto time. A backup was preserved and only that cached profile was moved out of Xcode's profile directory. Xcode obtained a renewed profile expiring **November 5, 2026 at 1:09 a.m. Toronto time**.

## Validation

- Signed Release build of 0.2.1: passed.
- Signature verification using the Mac trust services: passed.
- 36 route/schedule checks and 5 signing-date regression checks: passed.
- No simulator restarted and no code installed on the physical phone during this repair.
- Actual dragging, pinch zoom, pin selection and background departures still require on-phone verification. The provided console logs alone do not prove the single cause of the interaction failure.

After installing: dismiss any expiry notice, drag the map, pinch to zoom, tap to select a pin, and check Add stop and search. If interaction still fails, distinguish whether the rest of the screen responds and whether this happens with Xcode's debugger detached.
