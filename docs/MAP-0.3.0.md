# MobileGhost 0.3.0 — walking map repair

The default Walking map now uses the same OpenStreetMap tiles as desktop Ghost Transit. This replaces the Apple basemap with its limited nearby-path overlay. Walking routes use the same FOSSGIS pedestrian routing service as the desktop app. Apple Maps and satellite views remain available.

The former overlay requested at most 300 path segments within 1 km. An OpenStreetMap query around Waterloo Village 1 returned 1,438 segments on October 29, 2026. The new tile map has no such application-imposed segment cutoff and loads details as you pan and zoom. It includes visible attribution, HTTP caching, and a retry control for failed tile requests.

Opening the app still performs only one location lookup to center the map. No real-location dot or continuous tracking is enabled. iOS may return the simulated position while simulation is active.

Validation: signed generic-device Release build succeeded; 36 journey checks and 5 signing checks passed. A live pedestrian route near Village 1 returned 599.5 metres and 55 geometry points. Physical iPhone map gestures and visual appearance still require device verification; no simulator was launched.

Install by opening the existing MobileGhost Xcode project and pressing Command–R with your iPhone selected. Do not delete the existing app. The source archive is a backup of this revision, not an installable iPhone package.

OpenStreetMap coverage and public routing availability remain external dependencies. This update cannot guarantee that every physical path is mapped, current, publicly accessible, or routable.
