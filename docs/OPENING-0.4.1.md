# MobileGhost 0.4.1 — opening location, map camera, and signing repair

The app automatically requests a fresh location on initial launch and each return from the background, centers a 600-metre map view, and stops the lookup. There is no recenter button or user-location dot. Old lookups are cancelled on backgrounding; transient failures retry within a 15-second timeout. Permission denial or an unavailable fix leaves a clear message and the map usable. Centering uses the location iOS supplies, which can be simulated while spoofing.

Explicit camera commands now have their own revision. User pans and zooms no longer feed old regions back as camera commands, and repeated opening at the same coordinate still recenters. Removed gesture-tree scanning on every visible-region update. Walking tiles retain native map content underneath during load/failure. Close-zoom tiles now return their advertised 256×256 size; decoding and completion callbacks run on a bounded worker queue separate from request bookkeeping. The closer zoom limit remains 45 metres.

Only MobileGhost's expiring cached provisioning profile was backed up. Xcode issued a new profile; the embedded profile now expires November 11, 2026 at 12:52:13 p.m. America/Toronto. This replaces the previous November 5 expiry. The app's existing embedded-profile check can advance its old cached expiry after installation. Future Xcode reinstalls can still reuse a profile rather than renew it; the expiry remains tied to the signing profile.

Validation: signed generic iPhone Release build succeeded and strict signature verification passed. All 58 journey/recurrence/notification checks and 5 signing checks passed. Automatic centering, zoom rendering, and interaction still require verification on the physical phone; no simulator was launched.

Install by selecting the iPhone in the existing Xcode project and pressing Command–R. Keep the existing app installed so its routes and pairing data remain available. This source update does not install itself onto the phone.
