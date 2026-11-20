// Mobile Ghost additions, 2026-10-22. AGPL-3.0.
import Foundation

struct GeoPoint: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var isValid: Bool { latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) }
    func distance(to other: Self) -> Double {
        let r = Double.pi / 180
        let a = pow(sin((other.latitude-latitude)*r/2),2) + cos(latitude*r)*cos(other.latitude*r)*pow(sin((other.longitude-longitude)*r/2),2)
        return 6_371_000 * 2 * atan2(sqrt(min(1,a)),sqrt(max(0,1-a)))
    }
    func interpolated(to other: Self, fraction: Double) -> Self {
        let f = min(1,max(0,fraction))
        var delta = other.longitude-longitude
        if delta > 180 { delta -= 360 }; if delta < -180 { delta += 360 }
        var lon = longitude + delta*f
        if lon > 180 { lon -= 360 }; if lon < -180 { lon += 360 }
        return Self(latitude: latitude+(other.latitude-latitude)*f, longitude: lon)
    }
}
struct JourneyStop: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var point: GeoPoint
    var waitSeconds: Double = 0
    var departureSpeed: Double = 0 // zero inherits the current speed
}
struct JourneyLeg: Codable {
    var points: [GeoPoint]
    var distance: Double { zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to:$1.1) } }
    func position(at meters: Double) -> GeoPoint {
        guard let first = points.first else { return GeoPoint(latitude:0,longitude:0) }
        var remaining = max(0,meters)
        for (a,b) in zip(points,points.dropFirst()) {
            let d = a.distance(to:b)
            if d > 0 && remaining < d { return a.interpolated(to:b, fraction:remaining/d) }
            remaining -= d
        }
        return points.last ?? first
    }
}
struct JourneyPlan: Codable {
    var stops: [JourneyStop]
    var legs: [JourneyLeg]
    var mode: String
    var isValid: Bool {
        stops.count >= 2 && legs.count == stops.count-1 && stops.allSatisfy { $0.point.isValid && (0...86400).contains($0.waitSeconds) && ($0.departureSpeed == 0 || (1...160).contains($0.departureSpeed)) } && legs.allSatisfy { $0.points.count >= 2 && $0.points.allSatisfy(\.isValid) }
    }
    var distance: Double { legs.reduce(0) { $0+$1.distance } }
}
/// Value semantics let the controller commit progress only after the phone acknowledges it.
struct JourneyCursor {
    var plan: JourneyPlan
    var legIndex = 0
    var meters = 0.0
    var waiting = 0.0
    var speed: Double
    var finished = false
    init(plan: JourneyPlan, speed: Double) {
        self.plan = plan; self.speed = speed
        waiting = plan.stops.first?.waitSeconds ?? 0
        if let s = plan.stops.first?.departureSpeed, s > 0 { self.speed = s }
    }
    var point: GeoPoint { finished ? plan.stops.last!.point : plan.legs[legIndex].position(at:meters) }
    mutating func advance(seconds: Double) {
        guard plan.isValid, !finished, seconds.isFinite, seconds > 0, (1...160).contains(speed) else { return }
        var remaining = seconds
        while remaining > 0 && !finished {
            if waiting > 0 { let consumed = min(waiting,remaining); waiting -= consumed; remaining -= consumed; if remaining <= 0 { break } }
            let leg = plan.legs[legIndex]
            let time = max(0,leg.distance-meters)/(speed/3.6)
            if time > remaining { meters += remaining*speed/3.6; return }
            remaining -= time
            legIndex += 1; meters = 0
            if legIndex == plan.legs.count { finished = true; break }
            waiting = plan.stops[legIndex].waitSeconds
            if plan.stops[legIndex].departureSpeed > 0 { speed = plan.stops[legIndex].departureSpeed }
        }
    }
}

/// Switching apps is not an interruption. A gap in actual execution is.
enum BackgroundExecutionPolicy {
    static func mayTick(foreground: Bool, locationActive: Bool) -> Bool {
        foreground || locationActive
    }
    static func interrupted(elapsed: TimeInterval) -> Bool {
        !elapsed.isFinite || elapsed < 0 || elapsed > 3
    }
}


struct ScheduledJourney: Codable, Identifiable {
    var id = UUID()
    var name: String
    var plan: JourneyPlan
    var departure: Date
    var speed: Double
    var state = "Pending"
    var weeklyRepeat: WeeklyRepeat?
    var lastOutcome: String?
    var windowStart: Date?
    var windowSeconds: TimeInterval?
    var earliestDeparture: Date { windowStart ?? departure }
    var latestDeparture: Date { earliestDeparture.addingTimeInterval(windowSeconds ?? 0) }
    var reservedDuration: TimeInterval { duration + (windowSeconds ?? 0) }
    mutating func chooseDeparture(unit: Double = Double.random(in:0...1)) {
        guard let windowStart, let windowSeconds else { return }
        departure = windowStart.addingTimeInterval(windowSeconds * min(1,max(0,unit)))
    }
    var duration: TimeInterval {
        var currentSpeed = speed
        return plan.legs.enumerated().reduce(0) { total, item in
            let stop = plan.stops[item.offset]
            if stop.departureSpeed > 0 { currentSpeed = stop.departureSpeed }
            return total + stop.waitSeconds + item.element.distance / (currentSpeed / 3.6)
        }
    }
    var arrival: Date { departure.addingTimeInterval(duration) }
    func overlaps(_ other: Self) -> Bool {
        if weeklyRepeat == nil && other.weeklyRepeat == nil {
            return earliestDeparture < other.latestDeparture.addingTimeInterval(other.duration) && other.earliestDeparture < latestDeparture.addingTimeInterval(duration)
        }
        // Include a full seasonal cycle for differing time zones / DST.
        let end = max(departure,other.departure).addingTimeInterval(370*86400)
        let left = occurrences(until:end), right = other.occurrences(until:end)
        let leftDuration = reservedDuration, rightDuration = other.reservedDuration
        var i = 0, j = 0
        while i < left.count && j < right.count {
            if left[i] < right[j].addingTimeInterval(rightDuration) && right[j] < left[i].addingTimeInterval(leftDuration) { return true }
            if left[i].addingTimeInterval(leftDuration) <= right[j] { i += 1 } else { j += 1 }
        }
        return false
    }
    private func occurrences(until end: Date) -> [Date] {
        var dates = [earliestDeparture]
        while let rule = weeklyRepeat, let next = rule.next(after:dates.last!), next <= end, dates.count < 800 {
            dates.append(next)
        }
        return dates
    }
    var overlapsOwnRepeat: Bool {
        guard weeklyRepeat != nil else { return false }
        let dates = occurrences(until:departure.addingTimeInterval(370*86400))
        let travelTime = reservedDuration
        return zip(dates,dates.dropFirst()).contains { $0.addingTimeInterval(travelTime) > $1 }
    }
    mutating func finishOccurrence(_ outcome: String, now: Date) {
        lastOutcome = outcome
        if let next = weeklyRepeat?.next(after:max(now,earliestDeparture)) {
            departure = next
            if windowSeconds != nil { windowStart = next; chooseDeparture() }
            state = "Pending"
        } else { state = outcome }
    }
    var isValid: Bool { plan.isValid && (1...160).contains(speed) && departure.timeIntervalSince1970.isFinite && (weeklyRepeat == nil || weeklyRepeat!.isValid) && validWindow }
    var validWindow: Bool {
        if windowStart == nil && windowSeconds == nil { return true }
        guard let windowStart, let windowSeconds, windowStart.timeIntervalSince1970.isFinite,
              windowSeconds.isFinite, (1...86400).contains(windowSeconds) else { return false }
        return departure >= windowStart && departure <= latestDeparture
    }
}


enum DepartureDecision: Equatable { case wait, start, missed }
enum DeparturePolicy {
    static func decision(departure: Date, now: Date, armed: Bool, occupied: Bool, connected: Bool, latestDeparture: Date? = nil) -> DepartureDecision {
        let delay = now.timeIntervalSince(departure)
        guard delay >= 0 else { return .wait }
        if delay > 60 || (latestDeparture.map { now > $0 } ?? false) { return .missed }
        return armed && !occupied && connected ? .start : .wait
    }
}

/// Calendar weekdays: Sunday = 1 ... Saturday = 7. The saved zone keeps
/// a departure at the chosen local time even if the phone later travels.
struct WeeklyRepeat: Codable, Equatable {
    var weekdays: Set<Int>
    var hour: Int
    var minute: Int
    var timeZoneID: String
    var isValid: Bool {
        !weekdays.isEmpty && weekdays.allSatisfy { (1...7).contains($0) } &&
        (0...23).contains(hour) && (0...59).contains(minute) && TimeZone(identifier:timeZoneID) != nil
    }
    func next(after date: Date) -> Date? {
        guard isValid else { return nil }
        var calendar = Calendar(identifier:.gregorian)
        calendar.timeZone = TimeZone(identifier:timeZoneID)!
        return weekdays.compactMap { day in
            calendar.nextDate(after:date,matching:DateComponents(hour:hour,minute:minute,second:0,weekday:day),
                matchingPolicy:.nextTime,repeatedTimePolicy:.first,direction:.forward)
        }.min()
    }
    var summary: String {
        let names = [2:"Mon",3:"Tue",4:"Wed",5:"Thu",6:"Fri",7:"Sat",1:"Sun"]
        return [2,3,4,5,6,7,1].filter { weekdays.contains($0) }.compactMap { names[$0] }.joined(separator:", ")
    }
}

/// One notification per route, after acknowledged movement (not its initial
/// jump to the starting pin, waiting at a stop, or a failed device command).
struct RouteMovementNotice {
    var name: String?
    mutating func take(from: GeoPoint, to: GeoPoint, acknowledged: Bool) -> String? {
        guard acknowledged, from != to, let name else { return nil }
        self.name = nil
        return name
    }
}
