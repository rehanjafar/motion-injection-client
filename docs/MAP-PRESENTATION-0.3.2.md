# MobileGhost 0.3.2

Keeps the 45-metre minimum camera distance and Walking zoom levels through 22.

The map now has a rounded frame, an opening preparation view, a fade-in after tile activity settles, and a compact loading indicator during later map navigation. The loading presentation allows touches through and clears on interaction, location failure, tile failure, or a 15-second fallback. Reduced Motion is respected.

Tile HTTP caching grows to 64 MB memory / 256 MB disk. A separate 48 MB bounded cache reuses decoded source imagery at close zoom, where tiles are resampled to 256 pixels using high-quality interpolation. Only tiles requested by the map are loaded; no bulk area downloads. Network/cache freshness still comes from URLSession and HTTP headers. Close zoom enlarges existing detail rather than adding new map data.

Signing and pairing work remain off the main thread to keep controls responsive. No real-location marker or continuous tracking was added.

Validation: generic iPhone Release build and strict signing verification passed. Physical-device appearance, smoothness, and loading time have not been measured. No simulator was launched. Prior journey/signing checks are unchanged by this presentation update.

Install using Command–R in the existing Xcode project. Keep the installed app and its data.
