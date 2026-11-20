# MobileGhost 0.3.3

Rolled back 0.3.2 map presentation and rendering changes: removed the preparation overlay, fade-in, rounded frame, per-tile loading UI updates, decoded-image cache, and extra image resampling. Restored the 0.3.1 map implementation, including the 45-metre camera limit and zoom through level 22.

Restored 0.3.0 startup ordering for local signing-profile reads, pairing-file preparation, and legacy log cleanup. Restored the original opening-location lookup. Map/UI mutations remain on the main thread. Network downloads and device communication remain asynchronous to avoid freezing interaction.

The rollback does not establish which change caused the reported choppiness; actual frame timing requires profiling on the iPhone. No simulator was launched.

Install from the existing Xcode project with Command–R, keeping the existing app installed.

Validation: all 41 journey/signing logic checks passed. Compilation reached code signing; the signing process stalled waiting for macOS Security services and was stopped. A fully signed build was not verified for this revision.
