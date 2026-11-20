# MobileGhost 0.4.0 — weekly routes and movement notifications

## Use weekly schedules

1. Plan a route and set its speed and stop waits.
2. Turn on **Repeat weekly** and select any combination of weekdays.
3. Choose the first eligible date and departure time, then **Add to schedules**.
4. Open **Schedules** and tap **Arm** with LocalDevVPN connected and background location available.

The schedule repeats on the selected days until removed. Schedules show the next departure, repeat days, saved time zone, and previous outcome. One-time schedules remain supported, and existing saved schedules still load.

Each repeat uses the saved local time zone. Normal daylight-saving changes keep the same clock time. A nonexistent spring-forward time uses the next valid time; the repeated fall-back hour runs once, at its first occurrence. Missed dates are skipped rather than replayed. After reopening the app, re-arm departures.

A phone can follow only one route at a time. Saving checks for overlaps through the coming seasonal cycle (370 days beyond the later first departure), including a route overlapping its own next run. At execution, occupied/disconnected sessions retain the existing 60-second grace period and then mark the occurrence missed, advancing weekly routes to their next date.

## Movement notifications

Allow notifications when prompted after saving or starting a route. Settings also includes **Enable route notifications** and a link to iPhone notification settings.

A local notification is submitted after the phone acknowledges the first changed location along a route. Moving initially to its first pin, waiting there, and failed commands do not trigger it. Later updates and pause/resume do not duplicate it; each weekly run gets its own notification. Banners are supported while the app is open. Focus and iPhone notification permissions determine actual presentation and sound.

## Limits and verification

Recurring schedules do not bypass iOS background restrictions. Keep departures armed and VPN connected; force-quitting, iOS suspension, or a lost connection can prevent a run. Notifications announce actual accepted movement; they do not wake the app to execute a route.

58 journey/scheduling/notification-policy checks and 5 signing checks passed. Tests cover selected weekdays, week rollover, DST gaps and repeated hours, missed weeks, legacy saved data, future conflicts, and notification suppression/deduplication. Signed generic iPhone Release build and strict signature verification passed. Physical-device notification delivery and locked-screen execution have not been verified. No simulator was launched.

Install with Command–R from the existing Xcode project, keeping the installed app and its data.
