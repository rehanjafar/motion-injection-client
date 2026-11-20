// Mobile Ghost additions, 2026-10-22. AGPL-3.0.
import SwiftUI
import MapKit

struct GhostHomeView: View {
    @StateObject private var session = GhostSession()
    @StateObject private var openingLocation = CurrentLocationProvider()
    @State private var awaitingOpeningLocation = false
    @State private var didOpen = false
    @State private var needsOpeningCenter = true
    @State private var cameraRevision = 0
    @State private var locationHint: String?
    @Environment(\.scenePhase) private var phase
    @State private var camera: MapCameraPosition = .automatic
    @State private var centre = GeoPoint(latitude:0,longitude:0)
    @State private var selected: GeoPoint?
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var stops: [JourneyStop] = []
    @State private var nearby: [JourneyStop] = []
    @State private var saved: [JourneyStop] = []
    @State private var mode = "Walking"
    @State private var plan: JourneyPlan?
    @State private var working = false
    @State private var showSettings = false
    @State private var showLibrary = false
    @State private var showRoute = false
    @State private var showSchedules = false
    @State private var editingSchedule: ScheduledJourney?
    @State private var randomDeparture = false
    @State private var windowMinutes = 5
    @State private var routeName = ""
    @State private var walkingProvider = "OpenStreetMap"
    @State private var mapStyle = "Walking"
    @State private var tileReload = 0
    @State private var tileFailed = false
    @ObservedObject private var background = BackgroundLocationManager.shared
    @State private var repeatsWeekly = false
    @State private var repeatDays: Set<Int> = [2,3,4,5,6]
    @State private var departure = Date().addingTimeInterval(300)
    @State private var speed = 5.0
    @State private var nextWalkingRequest = Date.distantPast
    @State private var nextTransitQuery = Date.distantPast

    var body: some View {
        VStack(spacing:0) {
            header.padding(.horizontal,12).padding(.top,8)
            searchBar.padding(.horizontal,12).padding(.vertical,8)
            CampusMap(region:camera.region, cameraRevision:cameraRevision, style:mapStyle, reload:tileReload,
                selected:selected, simulated:session.current, stops:stops, busStops:nearby, legs:plan?.legs ?? [],
                onTap: { point in awaitingOpeningLocation = false; locationHint = nil; selected = point; query = ""; results = [] },
                onBusStop: { stop in select(stop.point); query = stop.name },
                onRegion: { region, movedByUser in
                    centre = GeoPoint(region.center)
                    if movedByUser { awaitingOpeningLocation = false; locationHint = nil; openingLocation.cancel() }
                }, onTileFailure: { tileFailed = true })
                .frame(minHeight:220,maxHeight:.infinity).clipped()
            VStack(spacing:5) {
                HStack {
                    Picker("Map",selection:$mapStyle) {
                        Text("Walking").tag("Walking")
                        Text("Apple").tag("Apple")
                        Text("Satellite").tag("Satellite")
                    }.pickerStyle(.segmented)
                    if working { ProgressView() }
                }
                HStack {
                    if mapStyle == "Walking" {
                        Link("© OpenStreetMap contributors",destination:URL(string:"https://www.openstreetmap.org/copyright")!)
                        Spacer()
                        Link("Report missing path",destination:URL(string:"https://www.openstreetmap.org/fixthemap")!)
                    }
                }.font(.system(size:10))
                if tileFailed && mapStyle == "Walking" {
                    HStack {
                        Text("Some map tiles failed to load.").font(.caption)
                        Button("Retry") { tileFailed = false; tileReload += 1 }.font(.caption.bold())
                    }
                }
            }.padding(.horizontal,12).padding(.vertical,6)
            controlPanel
        }
        .background(Color(uiColor:.systemGroupedBackground))
        .toolbar(.hidden,for:.navigationBar)
        .tint(.indigo)
        .sheet(isPresented:$showSettings) { SettingsView() }
        .sheet(isPresented:$showSchedules) { scheduleList }
        .sheet(isPresented:$showRoute) { routeEditor }
        .sheet(isPresented:$showLibrary) { library }
        .alert("Mobile Ghost",isPresented:Binding(get:{session.error != nil},set:{if !$0 { session.error = nil }})) { Button("OK") {session.error = nil} } message: { Text(session.error ?? "") }
        .onAppear {
            if let data = UserDefaults.standard.data(forKey:"ghostPlaces") { saved = (try? JSONDecoder().decode([JourneyStop].self,from:data)) ?? [] }
            if !didOpen { didOpen = true; needsOpeningCenter = false; centerOnOpeningLocation() }
        }
        .onChange(of:phase) { _, value in
            session.setForeground(value == .active)
            if value == .active && needsOpeningCenter { needsOpeningCenter = false; centerOnOpeningLocation() }
            else if value == .background { needsOpeningCenter = true; awaitingOpeningLocation = false; openingLocation.cancel() }
        }

    }
    /// One location request per opening; only moves the camera. It does not
    /// add a location marker, start tracking, or change simulation state.
    private func centerOnOpeningLocation() {
        awaitingOpeningLocation = true
        locationHint = "Finding current location…"
        openingLocation.locate { result in
            guard awaitingOpeningLocation else { return }
            awaitingOpeningLocation = false
            switch result {
            case .success(let coordinate):
                centre = GeoPoint(coordinate)
                camera = .region(MKCoordinateRegion(center:coordinate,latitudinalMeters:600,longitudinalMeters:600))
                cameraRevision += 1
                locationHint = nil
            case .failure(.denied):
                locationHint = "Allow location access in iPhone Settings to center the map automatically."
            case .failure(.unavailable):
                locationHint = "Current location unavailable. You can still search or move the map."
            }
        }
    }
    private var searchBar: some View {
        VStack(spacing:6) {
            if let locationHint { Text(locationHint).font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading) }
            HStack {
                Image(systemName:"magnifyingglass")
                TextField("Search place or coordinates",text:$query).submitLabel(.search)
                    .onSubmit { Task { await search() } }
                Button { Task { await search() } } label: { Image(systemName:"arrow.right.circle.fill") }
                    .disabled(working || query.isEmpty).accessibilityLabel("Search")
            }.padding(12).background(.regularMaterial,in:RoundedRectangle(cornerRadius:16))
            if !results.isEmpty {
                ScrollView {
                    VStack(alignment:.leading,spacing:0) {
                        ForEach(Array(results.prefix(4).enumerated()),id:\.offset) { _, item in
                            Button { select(GeoPoint(item.placemark.coordinate)); query = item.name ?? "Place"; results = [] } label: {
                                Text(item.name ?? "Place").frame(maxWidth:.infinity,alignment:.leading).padding(10)
                            }
                        }
                    }
                }.frame(maxHeight:140)
            }
        }
    }
    private var header: some View {
        HStack(spacing:12) {
            Image(systemName:"location.north.circle.fill").font(.largeTitle).foregroundStyle(.indigo)
            VStack(alignment:.leading,spacing:2) {
                Text("Ghost").font(.title2.bold())
                Text("YOUR LOCATION STUDIO").font(.system(size:9,weight:.semibold,design:.rounded)).tracking(2).foregroundStyle(.secondary)
            }
            Spacer()
            Button { showLibrary = true } label: { Image(systemName:"bookmark").frame(width:40,height:40).background(.quaternary,in:Circle()) }.accessibilityLabel("Saved places")
            Button { showSettings = true } label: { Image(systemName:"slider.horizontal.3").frame(width:40,height:40).background(.quaternary,in:Circle()) }.accessibilityLabel("Connection settings")
        }.padding(12).background(.regularMaterial,in:RoundedRectangle(cornerRadius:24))
    }
    private var controlPanel: some View {
        ScrollView { VStack(spacing:14) {
            Capsule().fill(.quaternary).frame(width:36,height:4).padding(.top,8)
            HStack(alignment:.top,spacing:10) {
                Image(systemName:session.running ? "location.fill" : "location.circle").font(.title2).foregroundStyle(.indigo)
                VStack(alignment:.leading,spacing:4) {
                    Text(session.running ? "On the move" : selected != nil ? "Selected location" : "Where to?").font(.headline)
                    Text(session.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                if session.busy { ProgressView() }
            }
            if let p = selected {
                HStack {
                    VStack(alignment:.leading,spacing:3) {
                        Text(query.isEmpty ? "Dropped pin" : query).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(String(format:"%.5f, %.5f",p.latitude,p.longitude)).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { saved.append(JourneyStop(name:query.isEmpty ? "Saved place \(saved.count+1)" : query,point:p)); persistPlaces() } label: { Image(systemName:"bookmark") }.accessibilityLabel("Save selected place")
                }
                HStack(spacing:10) {
                    Button { Task { await session.setLocation(p) } } label: { Label("Set location",systemImage:"location.fill").frame(maxWidth:.infinity).padding(.vertical,5) }.buttonStyle(.borderedProminent).disabled(session.busy)
                    Button { if stops.count < 12 { stops.append(JourneyStop(name:query.isEmpty ? "Stop \(stops.count+1)" : query,point:p)); plan = nil } } label: { Label("Add stop",systemImage:"plus").padding(.vertical,5) }.buttonStyle(.bordered).disabled(stops.count >= 12 || working)
                }
            } else { Text("Search a place or tap anywhere on the map.").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading) }
            if session.needsRestore {
                HStack {
                    if session.running { Button { session.pause() } label: { Image(systemName:"pause.fill") }.accessibilityLabel("Pause route") }
                    if session.canResume { Button { session.resume() } label: { Image(systemName:"play.fill") }.disabled(session.busy).accessibilityLabel("Resume route") }
                    Text("\(Int(speed)) km/h").font(.caption.monospacedDigit())
                    Slider(value:$speed,in:1...160,step:1,onEditingChanged: { editing in if !editing { session.applySpeed(speed) } }).disabled(session.busy)
                    Button("Restore") { Task { await session.restore() } }.font(.subheadline.weight(.semibold)).disabled(session.busy)
                }
            }
            Divider()
            HStack(spacing:0) {
                dockButton("Route",detail:"\(stops.count) stops",icon:"point.topleft.down.to.point.bottomright.curvepath") { showRoute = true }
                dockButton("Schedules",detail:session.schedulesArmed ? "Armed · \(session.pendingCount)" : "\(session.pendingCount) upcoming",icon:"calendar.badge.clock") { showSchedules = true }
                dockButton("Transit",detail:"Nearby stops",icon:"bus") { Task { await findBusStops() } }
            }
        }.padding(.horizontal,20).padding(.bottom,12)
        }.frame(height:selected == nil ? (session.needsRestore ? 270 : 225) : (session.needsRestore ? 340 : 285))
        .background(.regularMaterial,in:UnevenRoundedRectangle(topLeadingRadius:28,topTrailingRadius:28))
    }
    private func dockButton(_ title: String, detail: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action:action) {
            VStack(spacing:4) {
                Image(systemName:icon).font(.title3)
                Text(title).font(.caption.weight(.semibold))
                Text(detail).font(.system(size:10)).foregroundStyle(.secondary)
            }.frame(maxWidth:.infinity)
        }.buttonStyle(.plain).foregroundStyle(.indigo)
    }
    private var scheduleList: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label(session.schedulesArmed ? "Departures armed" : "Departures paused",systemImage:session.schedulesArmed ? "checkmark.shield.fill" : "pause.circle")
                        Spacer()
                        if session.schedulesArmed { Button("Disarm") { session.disarmSchedules() } }
                        else { Button("Arm") { session.armSchedules() }.disabled(session.pendingCount == 0) }
                    }
                    Label(background.canContinueInBackground ? "Background location active" : "Background location not active",systemImage:"location.circle")
                        .font(.caption).foregroundStyle(background.canContinueInBackground ? .green : .orange)
                    Text("Arm while the app is open, then you can lock your phone. Keep LocalDevVPN connected. iOS may interrupt execution; missed departures are marked for review, never silently replayed. Re-arm after restarting the app.").font(.caption).foregroundStyle(.secondary)
                }
                if let error = session.error { Section("Needs attention") { Text(error).foregroundStyle(.red) } }
                if session.schedules.isEmpty {
                    ContentUnavailableView("Your day, planned",systemImage:"calendar.badge.plus",description:Text("Build a route, choose a departure time, then add it here. You can save several departures."))
                }
                ForEach(session.schedules) { item in
                    Section {
                        VStack(alignment:.leading,spacing:10) {
                            HStack(alignment:.top) {
                                Text(item.departure,style:.time).font(.title2.bold()).monospacedDigit()
                                Spacer()
                                Text(item.state).font(.caption.bold()).padding(.horizontal,10).padding(.vertical,5).background(.quaternary,in:Capsule())
                            }
                            Text(item.name).font(.headline)
                            if item.windowSeconds != nil {
                                Label("Window: \(item.earliestDeparture.formatted(date:.omitted,time:.shortened))–\(item.latestDeparture.formatted(date:.omitted,time:.shortened))",systemImage:"shuffle")
                                    .font(.subheadline)
                                Text("Chosen start shown above").font(.caption).foregroundStyle(.secondary)
                            }
                            if let rule = item.weeklyRepeat {
                                Label("Every \(rule.summary)",systemImage:"repeat").font(.subheadline)
                                Text("Time zone: \(rule.timeZoneID)").font(.caption).foregroundStyle(.secondary)
                                if let outcome = item.lastOutcome { Text("Previous departure: \(outcome)").font(.caption).foregroundStyle(.secondary) }
                            }
                            Text(item.departure.formatted(date:.abbreviated,time:.omitted)).font(.caption).foregroundStyle(.secondary)
                            Label(String(format:"%@ · %.2f km · %.0f min",item.plan.mode,item.plan.distance/1000,item.duration/60),systemImage:"point.topleft.down.to.point.bottomright.curvepath").font(.caption).foregroundStyle(.secondary)
                            if item.state != "Running" {
                                HStack {
                                    Button("Edit") { session.error = nil; editingSchedule = item }.buttonStyle(.bordered)
                                    Spacer()
                                    Button("Remove",role:.destructive) { session.removeSchedule(item.id) }.buttonStyle(.borderless)
                                }.font(.caption)
                            }
                        }.padding(.vertical,6)
                    }
                }
            }.navigationTitle("Schedules")
            .sheet(item:$editingSchedule) { item in ScheduleEditor(session:session,item:item) }
            .toolbar { ToolbarItem(placement:.topBarTrailing) { Button("Done") { showSchedules = false } } }
        }
    }
    private var routeEditor: some View {
        NavigationStack {
            Form {
                Section("Journey details") {
                    TextField("Name this journey",text:$routeName)
                }
                Section("Route") {
                    Picker("Travel mode",selection:$mode) { Text("Walking").tag("Walking"); Text("Car").tag("Car"); Text("Bus (custom roads)").tag("Bus") }
                        .onChange(of:mode) { _, m in plan = nil; speed = m == "Walking" ? 5 : (m == "Car" ? 40 : 30) }
                    if mode == "Walking" {
                        Picker("Walking paths",selection:$walkingProvider) { Text("OpenStreetMap").tag("OpenStreetMap"); Text("Apple Maps").tag("Apple Maps") }
                            .onChange(of:walkingProvider) { _, _ in plan = nil }
                        Text("OpenStreetMap often includes smaller footpaths. Add intermediate pins to guide your route. Coverage varies; no provider includes every path.").font(.caption).foregroundStyle(.secondary)
                        Link("© OpenStreetMap contributors · Fix the map",destination:URL(string:"https://www.openstreetmap.org/copyright")!)
                    }
                    Text("Add 2–12 pins from the map. Bus mode follows roads between your selected stops, not an official transit service.").font(.caption).foregroundStyle(.secondary)
                    ForEach($stops) { $stop in
                        VStack(alignment:.leading) {
                            TextField("Stop name",text:$stop.name).font(.headline)
                            HStack { Text("Wait (seconds)"); TextField("0",value:$stop.waitSeconds,format:.number).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                            HStack { Text("Depart (km/h, 0 = inherit)"); TextField("0",value:$stop.departureSpeed,format:.number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                        }
                    }.onDelete { stops.remove(atOffsets:$0); plan = nil }.onMove { stops.move(fromOffsets:$0,toOffset:$1); plan = nil }
                    Button(working ? "Planning…" : "Plan route") { Task { await planRoute() } }.disabled(stops.count < 2 || working)
                }.disabled(session.busy || working)
                if let plan {
                    Section("Ready to travel") {
                        Label(String(format:"%.2f km · %@",plan.distance/1000,plan.mode),systemImage:"checkmark.circle.fill").font(.headline).foregroundStyle(.indigo)
                        HStack { Text("Speed"); Spacer(); Text("\(Int(speed)) km/h").monospacedDigit() }
                        Slider(value:$speed,in:1...160,step:1)
                        Text("Start moves the phone to the first stop. Allow background location to continue after switching apps.").font(.caption)
                        Button("Start route") { let snapshot = JourneyPlan(stops:stops,legs:plan.legs,mode:mode); session.applySpeed(speed); Task { await session.start(snapshot,name:routeName.isEmpty ? nil : routeName) }; showRoute = false }.disabled(session.busy || !timingsValid)
                        Toggle("Repeat weekly",isOn:$repeatsWeekly)
                        if repeatsWeekly {
                            VStack(alignment:.leading,spacing:8) {
                                Text("Repeat on").font(.subheadline)
                                ForEach([2,3,4,5,6,7,1],id:\.self) { day in
                                    Toggle(Calendar.current.weekdaySymbols[day-1],isOn:Binding(
                                        get:{ repeatDays.contains(day) },
                                        set:{ if $0 { repeatDays.insert(day) } else { repeatDays.remove(day) } }))
                                }
                            }
                            Text("Runs at the selected time on each chosen day, starting on or after the date below. Uses \(TimeZone.current.identifier), including daylight-saving changes.").font(.caption).foregroundStyle(.secondary)
                        }
                        DatePicker(repeatsWeekly ? "Start on or after" : "Departure",selection:$departure,in:Date()...Date().addingTimeInterval(30*86400))
                        Toggle("Random start within a window",isOn:$randomDeparture)
                        if randomDeparture {
                            Stepper("Window length: \(windowMinutes) min",value:$windowMinutes,in:1...1440)
                            Text("Between \(departure.formatted(date:.omitted,time:.shortened)) and \(departure.addingTimeInterval(Double(windowMinutes)*60).formatted(date:.abbreviated,time:.shortened)). A new time is picked for each repeat. Any waits at the first stop still apply.").font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Add to schedules") { session.schedule(JourneyPlan(stops:stops,legs:plan.legs,mode:mode),at:departure,name:routeName,initialSpeed:speed,weekdays:repeatsWeekly ? repeatDays : [],windowSeconds:randomDeparture ? Double(windowMinutes)*60 : nil); if session.error == nil { showRoute = false } }.disabled(session.busy || !timingsValid || (repeatsWeekly && repeatDays.isEmpty))
                        Text("Allow notifications to receive an alert when route movement starts. Notification preferences are in Settings.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error = session.error { Section("Needs attention") { Text(error).foregroundStyle(.red) } }
                if !timingsValid { Text("Waits must be 0–86,400 seconds. Departure speed must be 0 (inherit) or 1–160 km/h.").foregroundStyle(.red) }
            }
            .navigationTitle("Plan a journey")
            .toolbar { ToolbarItem(placement:.topBarLeading) { EditButton() }; ToolbarItem(placement:.topBarTrailing) { Button("Done") { showRoute = false } } }
        }
    }
    private var timingsValid: Bool { stops.allSatisfy { (0...86400).contains($0.waitSeconds) && ($0.departureSpeed == 0 || (1...160).contains($0.departureSpeed)) } }
    private var library: some View {
        NavigationStack {
            List {
                Section("Saved places") { ForEach(saved) { place in Button(place.name) { select(place.point); query = place.name; showLibrary = false } }.onDelete { saved.remove(atOffsets:$0); persistPlaces() } }
                Section("About") {
                    Text("Mobile Ghost 0.5.0 · iPhone location simulation")
                    Text("Independent derivative of TLocation and StikDebug. © Stephen Bove and contributors. Modified October 22, 2026. AGPL-3.0; no warranty.").font(.caption)
                    Link("Source code and license",destination:URL(string:"https://github.com/rehanjafar/mobile-ghost")!)
                }
            }.navigationTitle("Library").toolbar { Button("Done") { showLibrary = false } }
        }
    }
    private func persistPlaces() { UserDefaults.standard.set(try? JSONEncoder().encode(saved),forKey:"ghostPlaces") }
    private func select(_ point: GeoPoint) { awaitingOpeningLocation = false; locationHint = nil; selected = point; cameraRevision += 1; camera = .region(MKCoordinateRegion(center:point.coordinate,latitudinalMeters:1500,longitudinalMeters:1500)) }
    private func search() async {
        guard !working else { return }; working = true; defer { working = false }
        let values = query.split(separator:",").compactMap { Double($0.trimmingCharacters(in:.whitespaces)) }
        if values.count == 2 { let p = GeoPoint(latitude:values[0],longitude:values[1]); if p.isValid { select(p); results = []; return } }
        let request = MKLocalSearch.Request(); request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center:centre.coordinate,latitudinalMeters:10000,longitudinalMeters:10000)
        do { results = try await MKLocalSearch(request:request).start().mapItems; if results.isEmpty { session.error = "No matching places found." } } catch { session.error = error.localizedDescription }
    }
    private func planRoute() async {
        guard !working, stops.count >= 2, timingsValid else { return }
        working = true; plan = nil; defer { working = false }
        let snapshot = stops; let selectedMode = mode; let provider = walkingProvider
        do {
            var legs: [JourneyLeg] = []
            for (a,b) in zip(snapshot,snapshot.dropFirst()) {
                if selectedMode == "Walking" && provider == "OpenStreetMap" {
                    legs.append(try await walkingLeg(from:a.point,to:b.point))
                    continue
                }
                let request = MKDirections.Request()
                request.source = MKMapItem(placemark:MKPlacemark(coordinate:a.point.coordinate))
                request.destination = MKMapItem(placemark:MKPlacemark(coordinate:b.point.coordinate))
                request.transportType = selectedMode == "Walking" ? .walking : .automobile
                guard let route = try await MKDirections(request:request).calculate().routes.first else { throw URLError(.cannotParseResponse) }
                let line = route.polyline
                let points = (0..<line.pointCount).map { GeoPoint(line.points()[$0].coordinate) }
                guard points.count >= 2 else { throw URLError(.cannotParseResponse) }
                legs.append(JourneyLeg(points:points))
            }
            guard stops == snapshot, mode == selectedMode, walkingProvider == provider else { return }
            plan = JourneyPlan(stops:snapshot,legs:legs,mode:selectedMode)
        } catch { session.error = "Route could not be planned: \(error.localizedDescription). Choose points on connected roads or paths." }
    }
    private func walkingLeg(from a: GeoPoint, to b: GeoPoint) async throws -> JourneyLeg {
        let delay = nextWalkingRequest.timeIntervalSinceNow
        if delay > 0 { try await Task.sleep(nanoseconds:UInt64(delay * 1_000_000_000)) }
        nextWalkingRequest = Date().addingTimeInterval(1.1)
        let path = "\(a.longitude),\(a.latitude);\(b.longitude),\(b.latitude)"
        var request = URLRequest(url:URL(string:"https://routing.openstreetmap.de/routed-foot/route/v1/driving/\(path)?overview=full&geometries=geojson&radiuses=100;100")!)
        request.timeoutInterval = 30
        request.setValue("MobileGhost/0.2 (https://github.com/rehanjafar/mobile-ghost)",forHTTPHeaderField:"User-Agent")
        struct Reply: Decodable {
            struct Route: Decodable { struct Geometry: Decodable { var coordinates: [[Double]] }; var geometry: Geometry }
            var code: String
            var routes: [Route]?
        }
        let (data,response) = try await URLSession.shared.data(for:request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 8_000_000 else { throw URLError(.badServerResponse) }
        let reply = try JSONDecoder().decode(Reply.self,from:data)
        guard reply.code == "Ok", let coordinates = reply.routes?.first?.geometry.coordinates,
              coordinates.count >= 2, coordinates.allSatisfy({ $0.count == 2 }) else { throw URLError(.cannotParseResponse) }
        let points = coordinates.map { GeoPoint(latitude:$0[1],longitude:$0[0]) }
        guard points.allSatisfy(\.isValid) else { throw URLError(.cannotParseResponse) }
        return JourneyLeg(points:points)
    }
    private func findBusStops() async {
        guard !working else { return }
        guard Date() >= nextTransitQuery else { session.error = "Wait 30 seconds between bus-stop searches."; return }
        working = true; nextTransitQuery = Date().addingTimeInterval(30); defer { working = false }
        let q = "[out:json][timeout:20];(node[highway=bus_stop](around:1000,\(centre.latitude),\(centre.longitude));node[public_transport=platform][bus=yes](around:1000,\(centre.latitude),\(centre.longitude)););out body 500;"
        var request = URLRequest(url:URL(string:"https://overpass-api.de/api/interpreter")!); request.httpMethod = "POST"; request.timeoutInterval = 30
        var form = URLComponents(); form.queryItems = [URLQueryItem(name:"data",value:q)]; request.httpBody = form.percentEncodedQuery?.data(using:.utf8)
        request.setValue("application/x-www-form-urlencoded",forHTTPHeaderField:"Content-Type")
        struct Response: Decodable { struct Node: Decodable { var lat: Double; var lon: Double; var tags: [String:String]? }; var elements: [Node] }
        do {
            let (data,response) = try await URLSession.shared.data(for:request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count < 2_000_000 else { throw URLError(.badServerResponse) }
            let nodes = try JSONDecoder().decode(Response.self,from:data).elements
            nearby = nodes.prefix(500).map { JourneyStop(name:$0.tags?["name"] ?? "Bus stop",point:GeoPoint(latitude:$0.lat,longitude:$0.lon)) }.filter { $0.point.isValid }
            if nearby.isEmpty { session.error = "No mapped bus stops found within 1 km of the map centre." }
        } catch { session.error = "Bus-stop search failed: \(error.localizedDescription)" }
    }
}
