// Mobile Ghost additions, 2026-10-22. AGPL-3.0.
import SwiftUI
import MapKit

private enum HomePanel: Equatable { case place, route, schedules }

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
    @State private var searchPresentation = SearchPresentation()
    private var searchVisible: Bool {
        get { searchPresentation.isOpen }
        nonmutating set { if newValue { searchPresentation.open() } else { searchPresentation.close() } }
    }
    private var searchRaised: Bool { searchPresentation.stage == .raised }
    @State private var activeDock = "Route"
    @State private var panelExpanded = false
    @State private var presentedPanel: HomePanel?
    @State private var routeEditMode: EditMode = .inactive
    @Namespace private var dockNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @State private var showSettings = false
    @State private var showLibrary = false
    private var showRoute: Bool {
        get { presentedPanel == .route }
        nonmutating set { if newValue { presentedPanel = .route; searchVisible = false } else if presentedPanel == .route { presentedPanel = nil } }
    }
    private var showSchedules: Bool {
        get { presentedPanel == .schedules }
        nonmutating set { if newValue { presentedPanel = .schedules; searchVisible = false } else if presentedPanel == .schedules { presentedPanel = nil } }
    }
    private var panelVisible: Bool {
        get { presentedPanel != nil }
        nonmutating set { presentedPanel = newValue ? .place : nil }
    }
    @State private var editingSchedule: ScheduledJourney?
    @State private var randomDeparture = false
    @State private var windowMinutes = 5
    @State private var routeName = ""
    @State private var walkingProvider = "OpenStreetMap"
    @State private var mapStyle = "Apple"
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
        GeometryReader { geometry in
            ZStack {
                journeyMap.ignoresSafeArea()
                VStack(spacing:12) {
                    Spacer(minLength:8)
                    if let locationHint, !panelVisible && !searchVisible {
                        Text(locationHint).font(.caption).padding(10).ghostGlass(cornerRadius:16)
                            .padding(.horizontal,16)
                    }
                    if tileFailed && mapStyle == "Walking" && !panelVisible {
                        HStack {
                            Text("Walking tiles unavailable").font(.caption)
                            Button("Retry") { tileFailed = false; tileReload += 1 }
                        }.padding(10).ghostGlass(cornerRadius:16)
                    }
                    if panelVisible {
                        HStack { mapStyleMenu.ghostGlass(cornerRadius:20); Spacer() }.padding(.horizontal,16)
                    }
                    if let panel = presentedPanel {
                        panelContent(panel)
                            .frame(height:panelHeight(panel,in:geometry.size.height))
                            .padding(.horizontal,12)
                            .transition(.move(edge:.bottom).combined(with:.opacity))
                    }
                    if searchVisible && !results.isEmpty {
                        searchResults.padding(12).ghostGlass(cornerRadius:24).padding(.horizontal,16)
                    }
                    bottomDock.padding(.horizontal,16)
                        .padding(.bottom,searchRaised ? 12 : 0)
                    if mapStyle == "Walking" {
                        Link("© OpenStreetMap contributors",destination:URL(string:"https://www.openstreetmap.org/copyright")!)
                            .font(.system(size:10)).padding(.horizontal,8).padding(.vertical,3)
                            .background(.regularMaterial,in:Capsule())
                    }
                }.padding(.bottom,8)
            }
        }
        .toolbar(.hidden,for:.navigationBar)
        .preferredColorScheme(.dark)
        .tint(GhostPalette.accent)
        .animation(reduceMotion ? nil : .spring(response:0.44,dampingFraction:0.9),value:presentedPanel)
        .animation(reduceMotion ? nil : .spring(response:0.48,dampingFraction:0.9),value:searchVisible)
        .animation(reduceMotion ? nil : .easeInOut(duration:0.28),value:searchRaised)
        .animation(reduceMotion ? nil : .easeInOut(duration:0.22),value:panelExpanded)
        .sheet(isPresented:$showSettings) { SettingsView() }
        .sheet(isPresented:$showLibrary) { library }
        .alert("Mobile Ghost",isPresented:Binding(get:{session.error != nil},set:{if !$0 { session.error = nil }})) { Button("OK") {session.error = nil} } message: { Text(session.error ?? "") }
        .sheet(item:$editingSchedule) { item in ScheduleEditor(session:session,item:item) }
        .task(id:searchPresentation.requestID) {
            let request = searchPresentation.requestID
            guard searchVisible else { searchFocused = false; return }
            do {
                try await Task.sleep(for:.seconds(PresentationMotion.searchExpansionDelay))
                guard !Task.isCancelled, searchPresentation.raise(request:request) else { return }
                try await Task.sleep(for:.seconds(reduceMotion ? 0 : PresentationMotion.keyboardFocusDelay))
                guard !Task.isCancelled, searchPresentation.mayFocus(request:request) else { return }
                searchFocused = true
            } catch { return }
        }
        .onAppear {
            if let data = UserDefaults.standard.data(forKey:"ghostPlaces") { saved = (try? JSONDecoder().decode([JourneyStop].self,from:data)) ?? [] }
            if !didOpen { didOpen = true; needsOpeningCenter = false; centerOnOpeningLocation() }
        }
        .onChange(of:phase) { _, value in
            session.setForeground(value == .active)
            if value == .active && needsOpeningCenter { needsOpeningCenter = false; centerOnOpeningLocation() }
            else if value == .background { needsOpeningCenter = true; awaitingOpeningLocation = false; openingLocation.cancel(); panelVisible = false; searchVisible = false; searchFocused = false }
        }

    }
    private var journeyMap: some View {
        CampusMap(region:camera.region, cameraRevision:cameraRevision, style:mapStyle, reload:tileReload,
            selected:selected, simulated:session.current, stops:stops, busStops:nearby, legs:plan?.legs ?? [],
            onTap: { point in
                awaitingOpeningLocation = false; openingLocation.cancel(); locationHint = nil
                selected = point; panelVisible = true; query = ""; results = []; searchVisible = false; searchFocused = false
            },
            onBusStop: { stop in select(stop.point); query = stop.name },
            onRegion: { region, movedByUser in
                centre = GeoPoint(region.center)
                if movedByUser { awaitingOpeningLocation = false; locationHint = nil; openingLocation.cancel(); searchFocused = false }
            }, onTileFailure: { tileFailed = true })
            .ignoresSafeArea(edges:.top)
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
        HStack(spacing:12) {
            Image(systemName:"magnifyingglass").font(.system(size:20))
            TextField("Search place or coordinates",text:$query)
                .focused($searchFocused).submitLabel(.search).autocorrectionDisabled()
                .onSubmit { Task { await search() } }
            if working { ProgressView().controlSize(.small) }
            Button { searchVisible = false; searchFocused = false } label: {
                Image(systemName:"xmark").frame(width:44,height:44)
            }.accessibilityLabel("Close search")
        }.padding(.leading,18).padding(.trailing,6).frame(height:58)
    }
    private var searchResults: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:6) {
                ForEach(Array(results.prefix(4).enumerated()),id:\.offset) { _, item in
                    Button { select(GeoPoint(item.placemark.coordinate)); query = item.name ?? "Place"; results = [] } label: {
                        Label(item.name ?? "Place",systemImage:"mappin")
                            .frame(maxWidth:.infinity,alignment:.leading).padding(12)
                    }.buttonStyle(.plain)
                }
            }
        }.frame(maxHeight:180)
    }
    private var mapStyleItems: [GhostMenuItem] {
        [("Walking","Walking","figure.walk"),("Apple","Apple Maps","map"),("Satellite","Satellite","globe")].map { value in
            GhostMenuItem(id:value.0,title:value.1,symbol:value.2,selected:mapStyle == value.0) { mapStyle = value.0 }
        }
    }
    private var mapStyleMenu: some View {
        GhostDropdown(items:mapStyleItems) {
            HStack(spacing:8) {
                Image(systemName:"map")
                Text(mapStyle == "Apple" ? "Apple Maps" : mapStyle)
                Image(systemName:"chevron.down").font(.caption.weight(.semibold))
            }.font(.subheadline.weight(.medium)).padding(.horizontal,16).frame(height:46)
        }.accessibilityLabel("Choose map style")
    }
    @ViewBuilder private func panelContent(_ panel: HomePanel) -> some View {
        switch panel {
        case .place: controlPanel
        case .route:
            GhostPanelSurface(title:"Plan a journey",expanded:$panelExpanded,editable:true,close:{ showRoute = false }) {
                routeEditor
            }.environment(\.editMode,$routeEditMode)
        case .schedules:
            GhostPanelSurface(title:"Schedules",expanded:$panelExpanded,close:{ showSchedules = false }) {
                scheduleList
            }
        }
    }
    private func panelHeight(_ panel: HomePanel, in height: CGFloat) -> CGFloat {
        let available = max(140,height - 178)
        if panel == .place { return min(available,panelExpanded ? 470 : 330) }
        return min(available,height * (panelExpanded ? 0.80 : 0.69))
    }
    private var controlPanel: some View {
        GhostPanelSurface(title:session.running ? "On the move" : "Selected location",subtitle:session.status,
            expanded:$panelExpanded,close:{ panelVisible = false }) {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    if let locationHint { Text(locationHint).font(.caption).foregroundStyle(GhostPalette.secondary) }
                    if tileFailed && mapStyle == "Walking" {
                        HStack {
                            Text("Some walking tiles could not load.").font(.caption)
                            Button("Retry") { tileFailed = false; tileReload += 1 }
                        }
                    }
                    if let p = selected {
                        HStack {
                            VStack(alignment:.leading,spacing:5) {
                                Text(query.isEmpty ? "Dropped pin" : query).font(.headline).lineLimit(2)
                                Text(String(format:"%.5f, %.5f",p.latitude,p.longitude)).font(.caption.monospaced()).foregroundStyle(GhostPalette.secondary)
                            }
                            Spacer()
                            Button { saved.append(JourneyStop(name:query.isEmpty ? "Saved place \(saved.count+1)" : query,point:p)); persistPlaces() } label: {
                                Image(systemName:"bookmark").frame(width:44,height:44)
                            }.accessibilityLabel("Save selected place")
                        }
                        HStack(spacing:12) {
                            Button { Task { await session.setLocation(p) } } label: {
                                Label("Set location",systemImage:"location.fill").frame(maxWidth:.infinity).padding(.vertical,8)
                                    .foregroundStyle(Color(uiColor:.systemBackground))
                            }.buttonStyle(.borderedProminent).disabled(session.busy)
                            Button {
                                if stops.count < 12 { stops.append(JourneyStop(name:query.isEmpty ? "Stop \(stops.count+1)" : query,point:p)); plan = nil }
                            } label: {
                                Label("Add stop",systemImage:"plus").frame(maxWidth:.infinity).padding(.vertical,8)
                            }.buttonStyle(.bordered).disabled(stops.count >= 12 || working)
                        }
                    } else if !session.needsRestore {
                        Text("Tap the map to place a pin, or search for a place.")
                            .font(.subheadline).foregroundStyle(GhostPalette.secondary)
                    }
                    if session.needsRestore {
                        HStack {
                            if session.running { Button { session.pause() } label: { Image(systemName:"pause.fill").frame(width:44,height:44) }.accessibilityLabel("Pause route") }
                            if session.canResume { Button { session.resume() } label: { Image(systemName:"play.fill").frame(width:44,height:44) }.disabled(session.busy).accessibilityLabel("Resume route") }
                            Text("\(Int(speed)) km/h").font(.caption.monospacedDigit())
                            Spacer()
                            Button("Restore") { Task { await session.restore() } }.disabled(session.busy)
                        }
                        Slider(value:$speed,in:1...160,step:1,onEditingChanged: { editing in if !editing { session.applySpeed(speed) } })
                            .disabled(session.busy).accessibilityLabel("Movement speed")
                    }
                    if !stops.isEmpty {
                        Button { showRoute = true } label: {
                            HStack {
                                Image(systemName:"point.topleft.down.to.point.bottomright.curvepath")
                                Text("\(stops.count) route stops"); Spacer(); Text("Plan route"); Image(systemName:"arrow.right")
                            }.font(.subheadline).padding(14).background(.quaternary,in:RoundedRectangle(cornerRadius:16))
                        }.buttonStyle(.plain)
                    }
                    if working || session.busy { ProgressView().frame(maxWidth:.infinity) }
                }.padding(20)
            }
        }
    }

    private var bottomDock: some View {
        GhostGlassGroup {
            ZStack {
                if searchVisible {
                    searchBar.ghostGlass(cornerRadius:20,interactive:true)
                        .ghostMorph("dock-search",in:dockNamespace)
                        .transition(.opacity)
                } else {
                    HStack(spacing:10) {
                        GhostDropdown(items:settingsItems) {
                            Image(systemName:"gearshape").font(.system(size:20)).frame(width:48,height:48)
                        }.ghostGlass(cornerRadius:17,interactive:true)
                            .accessibilityLabel("Settings, saved places and map style")
                        GhostDockTabs(selection:$activeDock,openRoute:{ showRoute = true },openSchedules:{ showSchedules = true })
                        Button {
                            panelVisible = false; searchFocused = false; searchVisible = true
                        } label: {
                            Image(systemName:"magnifyingglass").font(.system(size:20)).frame(width:48,height:48)
                        }.ghostGlass(cornerRadius:17,interactive:true)
                            .ghostMorph("dock-search",in:dockNamespace)
                            .accessibilityLabel("Search places")
                    }.transition(.opacity)
                }
            }.frame(height:60)
        }
    }
    private var settingsItems: [GhostMenuItem] {
        mapStyleItems + [
            GhostMenuItem(id:"saved",title:"Saved places",symbol:"bookmark") { showLibrary = true },
            GhostMenuItem(id:"settings",title:"Connection settings",symbol:"gearshape") { showSettings = true }
        ]
    }
    private var scheduleList: some View {
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
            }.scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
    }
    private var routeEditor: some View {
            Form {
                if session.needsRestore {
                    Section("Active movement") {
                        Text(session.status)
                        if session.running { Button("Pause route") { session.pause() } }
                        if session.canResume { Button("Resume route") { session.resume() }.disabled(session.busy) }
                        Button("Restore location") { Task { await session.restore() } }.disabled(session.busy)
                    }
                }
                Section("Journey details") {
                    TextField("Name this journey",text:$routeName)
                }
                Section("Route") {
                    GhostDropdown(items:[("Walking","figure.walk"),("Car","car"),("Bus","bus")].map { value in
                        GhostMenuItem(id:value.0,title:value.0,symbol:value.1,selected:mode == value.0) {
                            mode = value.0; plan = nil; speed = mode == "Walking" ? 5 : mode == "Car" ? 40 : 30
                        }
                    }) { HStack { Text("Travel mode"); Spacer(); Text(mode); Image(systemName:"chevron.down") } }
                    if mode == "Bus" {
                        Button("Find nearby transit stops") { showRoute = false; Task { await findBusStops() } }
                    }
                    if mode == "Walking" {
                        GhostDropdown(items:["OpenStreetMap","Apple Maps"].map { provider in
                            GhostMenuItem(id:provider,title:provider,symbol:"map",selected:walkingProvider == provider) {
                                walkingProvider = provider; plan = nil
                            }
                        }) { HStack { Text("Walking paths"); Spacer(); Text(walkingProvider); Image(systemName:"chevron.down") } }
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
                        Label(String(format:"%.2f km · %@",plan.distance/1000,plan.mode),systemImage:"checkmark.circle.fill").font(.headline).foregroundStyle(GhostPalette.accent)
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
            .scrollContentBackground(.hidden)
    }
    private var timingsValid: Bool { stops.allSatisfy { (0...86400).contains($0.waitSeconds) && ($0.departureSpeed == 0 || (1...160).contains($0.departureSpeed)) } }
    private var library: some View {
        NavigationStack {
            List {
                Section("Saved places") { ForEach(saved) { place in Button(place.name) { select(place.point); query = place.name; showLibrary = false } }.onDelete { saved.remove(atOffsets:$0); persistPlaces() } }
                Section("About") {
                    Text("Mobile Ghost 0.7.0 · iPhone location simulation")
                    Text("Independent derivative of TLocation and StikDebug. © Stephen Bove and contributors. Modified October 22, 2026. AGPL-3.0; no warranty.").font(.caption)
                    Link("Source code and license",destination:URL(string:"https://github.com/rehanjafar/mobile-ghost")!)
                }
            }.navigationTitle("Library").toolbar { Button("Done") { showLibrary = false } }
        }
    }
    private func persistPlaces() { UserDefaults.standard.set(try? JSONEncoder().encode(saved),forKey:"ghostPlaces") }
    private func select(_ point: GeoPoint) { awaitingOpeningLocation = false; locationHint = nil; selected = point; panelVisible = true; searchVisible = false; searchFocused = false; cameraRevision += 1; camera = .region(MKCoordinateRegion(center:point.coordinate,latitudinalMeters:1500,longitudinalMeters:1500)) }
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
