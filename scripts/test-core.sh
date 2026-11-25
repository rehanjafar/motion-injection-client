#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
swiftc -module-cache-path .build/module-cache MobileGhost/Core/Journey.swift Tests/JourneyChecks.swift -o .build/journey-checks
.build/journey-checks

swiftc -module-cache-path .build/module-cache MobileGhost/Support/AppSigningInfo.swift MobileGhost/Support/UserDefaults+Keys.swift Tests/SigningChecks.swift -o .build/signing-checks
.build/signing-checks

swiftc -module-cache-path .build/module-cache MobileGhost/Core/PresentationMotion.swift Tests/PresentationChecks.swift -o .build/presentation-checks
.build/presentation-checks
