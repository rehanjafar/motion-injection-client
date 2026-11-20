# MobileGhost 0.3.1

## Changes

- Reduced minimum camera distance from 450 to 45 metres.
- Walking tiles support zoom levels through 22 by cropping and magnifying the existing level-19 imagery. This enlarges mapped detail; it does not invent more detailed map data.
- Concurrent requests for the same source tile share one download. Existing HTTP and disk caching remain enabled.
- Signing-profile loading and parsing, pairing-file preparation during connection startup, and legacy log cleanup run off the main thread.
- Expiry warnings wait for the installed-profile check so an old cached signature cannot trigger the startup warning prematurely.
- Opening location lookup uses 100-metre requested accuracy instead of 10 metres, with an eight-second timeout after permission is granted. No real-location dot or continuous tracking was added.

## Validation

Generic iPhone Release build and signing verification passed. All 36 journey and 5 signing checks passed. No simulator was launched. Actual launch time, close-zoom appearance, and gestures have not been measured on a physical iPhone; these changes address identified startup work without claiming a measured speedup.

Install through the existing Xcode project with Command–R. Keep the existing app installed. To judge normal launch speed, stop Xcode's running session and open the app from the iPhone home screen.
