# MobileGhost 0.2 validation — October 29, 2026

- Final unsigned iPhone device build: passed (Xcode 27.1).
- Pure route and scheduling checks: 36 passed, including persistence, overlapping departures, late departures, waits and speed changes.
- Live walking directions: FOSSGIS returned a 952.4 m route with 101 points for sample Waterloo coordinates.
- Live walking-path overlay: Overpass GET returned 300 paths with 1,637 geometry points. POST was rejected in this environment; the overlay uses GET.
- Home screen inspected in an iPhone simulator preview using stubbed device services. Spacing was tightened afterward and the final SwiftUI code compiled successfully.
- Simulator PosterBoard crashed independently during preview testing. Its crash report identifies launchd_sim and the test simulator. The simulator was shut down; no further simulator tests were run. The planned controller integration run was not executed.
- NOT verified: installation on the physical phone, background developer-tunnel survival, locked-screen scheduled departures, long-duration execution, or actual positions reported by other apps.

Schedules use an active foreground-started Core Location session. iOS can suspend or terminate the app. This is best-effort locked-screen execution, not a guaranteed exact-time wakeup service. A suspended/terminated app cannot promise a departure. Force-quit and relaunch require re-arming.
