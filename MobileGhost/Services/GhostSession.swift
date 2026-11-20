// Mobile Ghost additions, 2026-10-22. AGPL-3.0.
import SwiftUI
import MapKit

extension GeoPoint {
    init(_ c: CLLocationCoordinate2D) { latitude = c.latitude; longitude = c.longitude }
    var coordinate: CLLocationCoordinate2D { .init(latitude:latitude,longitude:longitude) }
}

@MainActor final class GhostSession: ObservableObject {
    @Published var status = "Ready to select a location"
    @Published var error: String?
    @Published var busy = false
    @Published var current: GeoPoint?
    @Published var running = false
    @Published var speed = 5.0
    @Published private(set) var schedules: [ScheduledJourney] = []
    @Published private(set) var schedulesArmed = false
    private var activeScheduleID: UUID?
    private var movementNotice = RouteMovementNotice()
    var scheduled: Date? { schedules.filter { $0.state == "Pending" }.map(\.departure).min() }
    var pendingCount: Int { schedules.filter { $0.state == "Pending" }.count }
    @Published var needsRestore = UserDefaults.standard.bool(forKey:"ghostNeedsRestore")
    private var cursor: JourneyCursor?
    private var timer: Timer?
    private var lastTick = Date()
    private var foreground = true
    private var refreshEnabled = false
    init() {
        if needsRestore { status = "Previous session needs review. Reconnect and restore." }
        if let data = UserDefaults.standard.data(forKey:"ghostLastPoint") { current = try? JSONDecoder().decode(GeoPoint.self,from:data) }
        if let data = UserDefaults.standard.data(forKey:"ghostSchedules"),
           let saved = try? JSONDecoder().decode([ScheduledJourney].self, from:data) {
            schedules = saved.filter(\.isValid).map { item in
                var item = item
                if item.state == "Running" { item.finishOccurrence("Interrupted",now:Date()) }
                if item.state == "Pending" && item.departure < Date() { item.finishOccurrence("Missed",now:Date()) }
                return item
            }
        }
        schedules.sort { $0.departure < $1.departure }
        persistSchedules()
        let timer = Timer(timeInterval:1, repeats:true) { [weak self] _ in Task { @MainActor in await self?.tick() } }
        RunLoop.main.add(timer, forMode:.common)
        self.timer = timer
    }
    func setForeground(_ active: Bool) {
        foreground = active
        if !active {
            if needsRestore && !BackgroundLocationManager.shared.canContinueInBackground {
                running = false
                status = "Background location permission needed. Last simulated position may remain."
            }
        }
        // Preserve the timestamp: returning after actual suspension must not hide
        // a missed interval and silently resume movement.

    }
    private func command(_ point: GeoPoint?) async -> Int32 {
        let ip = DeviceConnectionContext.targetIPAddress
        return await withCheckedContinuation { continuation in
            LocationSimulationCommandQueue.shared.async {
                let path = PairingFileStore.prepareURL().path
                let code: Int32
                if let point { code = simulate_location(ip,point.latitude,point.longitude,path) }
                else { code = clear_simulated_location() }
                continuation.resume(returning:code)
            }
        }
    }
    private func accepted(_ point: GeoPoint) {
        current = point; needsRestore = true; refreshEnabled = true
        UserDefaults.standard.set(true,forKey:"ghostNeedsRestore")
        UserDefaults.standard.set(try? JSONEncoder().encode(point),forKey:"ghostLastPoint")
        LocationSimulationSession.setMaintained(true)
        if foreground { BackgroundLocationManager.shared.requestStart() }
    }
    private func failure(_ code: Int32) {
        movementNotice.name = nil
        interruptActiveSchedule(); disarmSchedules(); running = false; refreshEnabled = false
        BackgroundLocationManager.shared.requestStop()
        error = "Device operation failed (\(code)). Reconnect LocalDevVPN and retry. The last simulated location may remain."
        status = "Connection needs attention"
    }
    func setLocation(_ point: GeoPoint) async {
        guard !busy, point.isValid else { return }
        movementNotice.name = nil
        interruptActiveSchedule(); running = false; cursor = nil; busy = true
        defer { busy = false }
        BackgroundLocationManager.shared.requestStart()
        let code = await command(point)
        if code == 0 { accepted(point); status = "Holding selected location — command accepted" } else { failure(code) }
    }
    func start(_ plan: JourneyPlan, scheduleID: UUID? = nil, name: String? = nil) async {
        guard !busy, plan.isValid else { return }
        interruptActiveSchedule(); activeScheduleID = scheduleID; running = false; busy = true
        defer { busy = false }
        movementNotice.name = name ?? "\(plan.stops.first!.name) → \(plan.stops.last!.name)"
        if foreground { await RouteNotifications.shared.requestPermission() }
        BackgroundLocationManager.shared.requestStart()
        let next = JourneyCursor(plan:plan,speed:speed)
        let code = await command(next.point)
        if code == 0 { cursor = next; speed = next.speed; accepted(next.point); running = foreground || BackgroundLocationManager.shared.canContinueInBackground; lastTick = Date(); status = running ? "Following route" : "Paused — background location permission needed" }
        else { failure(code) }
    }
    func pause() { running = false; status = "Paused — holding last location" }
    func resume() {
        guard !busy, let cursor, !cursor.finished, foreground else { return }
        BackgroundLocationManager.shared.requestStart()
        refreshEnabled = true; running = true; lastTick = Date(); status = "Following route"
    }
    var canResume: Bool { cursor != nil && cursor?.finished == false && !running }
    func applySpeed(_ value: Double) {
        guard value.isFinite, (1...160).contains(value), !busy else { return }
        speed = value; cursor?.speed = value
    }
    func schedule(_ plan: JourneyPlan, at date: Date, name: String = "", initialSpeed: Double? = nil, weekdays: Set<Int> = [], windowSeconds: TimeInterval? = nil) {
        error = nil
        guard !busy, plan.isValid, date.timeIntervalSinceNow > 0, date.timeIntervalSinceNow <= 30*86400 else { error = "Choose a departure within the next 30 days."; return }
        let calendar = Calendar.current
        let rule = weekdays.isEmpty ? nil : WeeklyRepeat(weekdays:weekdays,hour:calendar.component(.hour,from:date),
            minute:calendar.component(.minute,from:date),timeZoneID:calendar.timeZone.identifier)
        let minuteStart = calendar.dateInterval(of:.minute,for:date)!.start
        let firstDeparture = rule?.next(after:max(Date(),minuteStart.addingTimeInterval(-1))) ?? date
        var item = ScheduledJourney(name:name.isEmpty ? "\(plan.stops.first!.name) → \(plan.stops.last!.name)" : name,
                                    plan:plan, departure:firstDeparture, speed:initialSpeed ?? speed, weeklyRepeat:rule)
        if let windowSeconds { item.windowStart = firstDeparture; item.windowSeconds = windowSeconds; item.chooseDeparture() }
        guard saveSchedule(item,replacing:nil) else { return }
        status = "Departure saved. Arm departures before locking your phone."
        Task { await RouteNotifications.shared.requestPermission() }
    }
    @discardableResult func saveSchedule(_ candidate: ScheduledJourney, replacing id: UUID?) -> Bool {
        error = nil
        guard !busy, id == nil || (id != activeScheduleID && schedules.contains(where:{ $0.id == id && $0.state != "Running" })) else {
            error = "Wait until this route has stopped before editing it."; return false
        }
        var item = candidate
        if let id { item.id = id }
        guard item.isValid, item.earliestDeparture > Date(), item.earliestDeparture.timeIntervalSinceNow <= 37*86400 else {
            error = "Choose a future departure, a valid window of up to 24 hours, and speed from 1–160 km/h."; return false
        }
        guard !item.overlapsOwnRepeat else { error = "This route or departure window overlaps its next repeat. Choose fewer days or a shorter window."; return false }
        guard !schedules.contains(where: {  $0.id != id && ($0.state == "Pending" || $0.state == "Running") && $0.overlaps(item) }) else {
            error = "This departure window overlaps another route. One phone can follow only one route at a time."; return false
        }
        item.state = "Pending"
        if let id, let index = schedules.firstIndex(where: { $0.id == id }) { schedules[index] = item }
        else { schedules.append(item) }
        schedules.sort { $0.departure < $1.departure }; persistSchedules()
        status = "Schedule saved."
        return true
    }
    func armSchedules() {
        guard foreground, pendingCount > 0, TunnelManager.shared.isConnected, MountingProgress.shared.coolisMounted else {
            error = "Open MobileGhost with LocalDevVPN connected and the developer image ready, then arm departures."; return
        }
        BackgroundLocationManager.shared.requestStart()
        guard BackgroundLocationManager.shared.canContinueInBackground else {
            error = "Allow location access, then tap Arm again. Background location must be active before locking your phone."; return
        }
        schedulesArmed = true; lastTick = Date()
        Task { await RouteNotifications.shared.requestPermission() }
        status = "Departures armed. Keep VPN connected; do not force-quit."
    }
    func disarmSchedules() {
        schedulesArmed = false
        if !needsRestore { BackgroundLocationManager.shared.requestStop() }
    }
    func removeSchedule(_ id: UUID) {
        guard id != activeScheduleID else { return }
        schedules.removeAll { $0.id == id }; persistSchedules()
        if pendingCount == 0 { disarmSchedules() }
    }
    private func persistSchedules() {
        UserDefaults.standard.set(try? JSONEncoder().encode(schedules), forKey:"ghostSchedules")
    }
    private func setScheduleState(_ id: UUID, _ state: String) {
        if let index = schedules.firstIndex(where: { $0.id == id }) {
            if ["Completed","Missed","Interrupted"].contains(state) { schedules[index].finishOccurrence(state,now:Date()) }
            else { schedules[index].state = state }
            schedules.sort { $0.departure < $1.departure }
            persistSchedules()
        }
    }
    private func interruptActiveSchedule() {
        if let id = activeScheduleID { setScheduleState(id, "Interrupted"); activeScheduleID = nil }
    }
    func restore() async {
        guard !busy else { return }
        movementNotice.name = nil
        disarmSchedules(); interruptActiveSchedule(); running = false; busy = true
        defer { busy = false }
        // After process restart, reopen a session at the last acknowledged point before clearing.
        if !LocationSimulationSession.isOpen, let current {
            let code = await command(current)
            guard code == 0 else { failure(code); return }
        }
        let code = await command(nil)
        if code == 0 {
            cursor = nil; current = nil; needsRestore = false; refreshEnabled = false
            LocationSimulationSession.setMaintained(false)
            BackgroundLocationManager.shared.requestStop()
            UserDefaults.standard.removeObject(forKey:"ghostLastPoint")
            UserDefaults.standard.set(false,forKey:"ghostNeedsRestore")
            status = "Restore accepted. Check Maps for your real position."
        } else { failure(code) }
    }
    private func tick() async {
        let now = Date(); let elapsed = now.timeIntervalSince(lastTick); lastTick = now
        guard BackgroundExecutionPolicy.mayTick(foreground: foreground, locationActive: BackgroundLocationManager.shared.canContinueInBackground) else {
            if running { pause(); status = "Paused — background location permission needed" }
            return
        }
        if !busy, let item = schedules.first(where: { $0.state == "Pending" && $0.departure <= now }) {
            switch DeparturePolicy.decision(departure:item.departure, now:now, armed:schedulesArmed,
                occupied:running || canResume, connected:TunnelManager.shared.isConnected && MountingProgress.shared.coolisMounted,
                latestDeparture:item.windowSeconds == nil ? nil : item.latestDeparture) {
            case .missed:
                setScheduleState(item.id, "Missed")
                status = "Missed departure: session busy, delayed, or disconnected. Review Schedules."
            case .start:
                setScheduleState(item.id, "Running")
                speed = item.speed; await start(item.plan, scheduleID:item.id, name:item.name); return
            case .wait: break
            }
        }
        guard !busy, refreshEnabled, needsRestore, let point = current else { return }
        if running && BackgroundExecutionPolicy.interrupted(elapsed: elapsed) { pause(); status = "Paused after a delayed update. Resume to continue."; return }
        let wasRunning = running
        var next = cursor
        if running { next?.advance(seconds:min(2,elapsed)) }
        let target = running ? (next?.point ?? point) : point
        busy = true
        let code = await command(target)
        busy = false
        if code == 0 {
            if wasRunning, let name = movementNotice.take(from:point,to:target,acknowledged:true) {
                RouteNotifications.shared.routeStarted(name)
            }
            accepted(target)
            if wasRunning { cursor = next; speed = next?.speed ?? speed; if next?.finished == true { running = false; if let id = activeScheduleID { setScheduleState(id, "Completed"); activeScheduleID = nil }; status = "Arrived — holding destination" } }
        } else { failure(code) }
    }
}
