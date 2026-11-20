# MobileGhost 0.5.0 — editable schedules and random departure windows

Open Schedules and choose Edit under a saved route. You can change its name, departure date/time, initial speed, selected weekdays, and random departure window. Saving updates the existing schedule while preserving its route geometry and stops. Running routes cannot be edited; if a route starts while the editor is open, saving is blocked. Cancel discards edits. Saving a completed/missed one-time schedule as a future departure makes it pending again.

For a random start between 9:35 and 9:40, select 9:35 as the departure and enable Random start within a window with a length of 5 minutes. The window length supports 1–1,440 minutes and can cross midnight. Existing stop waits still apply after the route starts at its first pin.

A random instant is selected uniformly within the window when an occurrence is created and stored with the schedule. Reopening the app does not reroll it. Editing name or speed alone retains the chosen instant. Changing the time, days, or window picks a new instant. Weekly repeats select a new instant inside each occurrence's own window. Windows are elapsed durations from the local calendar start; repeat start times retain their saved zone and existing DST policy.

Conflict checks reserve the entire departure window plus travel/wait duration, including future weekly occurrences through the existing seasonal horizon. This is deliberately stricter than checking only the randomly chosen instant. Runtime still prevents simultaneous routes. An occurrence cannot start beyond the end of its window; the existing 60-second lateness limit can also mark it missed earlier. Missed recurring occurrences advance to the next selected day rather than replaying.

Existing exact-time schedules load without modification. Weekly repeats, notifications on actual acknowledged movement, automatic opening centering, and closer zoom remain in place. iOS background execution and VPN availability still govern actual departure execution.

Validation: 75 journey/schedule/window/notification-policy checks plus 5 signing checks passed. Tests cover persisted random choices, both endpoints, repeat generation, invalid windows, whole-window conflicts, deadline enforcement, midnight crossing, and legacy data. Signed generic iPhone Release build and strict signature verification passed. Physical iPhone interaction with the editor and real-time departures still requires device verification. No simulator was launched.

Install with Command–R from the existing Xcode project and keep the existing app installed. Re-arm departures after restarting.
