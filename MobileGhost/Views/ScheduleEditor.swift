import SwiftUI

struct ScheduleEditor: View {
    @ObservedObject var session: GhostSession
    let original: ScheduledJourney
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var departure: Date
    @State private var speed: Double
    @State private var repeats: Bool
    @State private var days: Set<Int>
    @State private var randomWindow: Bool
    @State private var minutes: Int
    private var zone: TimeZone { original.weeklyRepeat.flatMap { TimeZone(identifier:$0.timeZoneID) } ?? .current }
    init(session: GhostSession, item: ScheduledJourney) {
        self.session = session; original = item
        _name = State(initialValue:item.name)
        _departure = State(initialValue:max(item.earliestDeparture,Date().addingTimeInterval(300)))
        _speed = State(initialValue:item.speed)
        _repeats = State(initialValue:item.weeklyRepeat != nil)
        _days = State(initialValue:item.weeklyRepeat?.weekdays ?? [2,3,4,5,6])
        _randomWindow = State(initialValue:item.windowSeconds != nil)
        _minutes = State(initialValue:max(1,Int((item.windowSeconds ?? 300)/60)))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Journey") {
                    TextField("Name",text:$name)
                    LabeledContent("Route",value:original.plan.mode)
                    HStack { Text("Speed"); Spacer(); Text("\(Int(speed)) km/h") }
                    Slider(value:$speed,in:1...160,step:1)
                }
                Section("Departure") {
                    DatePicker(randomWindow ? "Window starts" : "Departure",selection:$departure,in:Date()...Date().addingTimeInterval(30*86400))
                    Toggle("Random start within a window",isOn:$randomWindow)
                    if randomWindow {
                        Stepper("Window length: \(minutes) min",value:$minutes,in:1...1440)
                        Text("Between \(departure.formatted(date:.abbreviated,time:.shortened)) and \(departure.addingTimeInterval(Double(minutes)*60).formatted(date:.abbreviated,time:.shortened))")
                        Text("A start time is picked once for each occurrence and saved. The route will not start after this window ends. Any waits at the first stop still apply.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Repeat") {
                    Toggle("Repeat weekly",isOn:$repeats)
                    if repeats {
                        ForEach([2,3,4,5,6,7,1],id:\.self) { day in
                            Toggle(Calendar.current.weekdaySymbols[day-1],isOn:Binding(
                                get:{ days.contains(day) },
                                set:{ if $0 { days.insert(day) } else { days.remove(day) } }))
                        }
                        Text("Time zone: \(zone.identifier)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error = session.error { Section { Text(error).foregroundStyle(.red) } }
            }
            .environment(\.timeZone,zone)
            .navigationTitle("Edit schedule")
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button("Save") { save() }.disabled(session.busy || (repeats && days.isEmpty)) }
            }
        }
    }
    private func save() {
        var item = original
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = zone
        let rule = repeats ? WeeklyRepeat(weekdays:days,hour:calendar.component(.hour,from:departure),minute:calendar.component(.minute,from:departure),timeZoneID:zone.identifier) : nil
        let start = rule?.next(after:max(Date(),calendar.dateInterval(of:.minute,for:departure)!.start.addingTimeInterval(-1))) ?? departure
        let width: TimeInterval? = randomWindow ? Double(minutes)*60 : nil
        item.name = name.trimmingCharacters(in:.whitespacesAndNewlines)
        if item.name.isEmpty { item.name = original.name }
        item.speed = speed; item.weeklyRepeat = rule
        // Name/speed-only edits retain the chosen start for this occurrence.
        if start != original.earliestDeparture || width != original.windowSeconds || rule != original.weeklyRepeat {
            item.departure = start; item.windowStart = randomWindow ? start : nil; item.windowSeconds = width
            item.chooseDeparture()
        }
        if session.saveSchedule(item,replacing:original.id) { dismiss() }
    }
}
