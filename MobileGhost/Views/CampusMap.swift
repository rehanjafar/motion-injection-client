import SwiftUI
import MapKit
import CoreImage

/// Same OpenStreetMap Carto tiles as Ghost Transit. Only visible tiles are
/// requested; URLSession honours HTTP cache headers and keeps a disk cache.
final class WalkingMapTiles: MKTileOverlay {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity:32*1024*1024,diskCapacity:128*1024*1024,diskPath:"walking-map-tiles")
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.timeoutIntervalForRequest = 20
        configuration.httpAdditionalHeaders = ["User-Agent":"MobileGhost/0.3 (+https://github.com/rehanjafar/mobile-ghost)"]
        return URLSession(configuration:configuration)
    }()
    private static let requestQueue = DispatchQueue(label:"walking-map-tile-requests")
    private static var pending: [URL: [(Data?, URLResponse?, Error?) -> Void]] = [:]
    // Close zooms reuse a parent tile. Share in-flight downloads between children.
    private static func load(_ request: URLRequest, completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
        guard let url = request.url else { completion(nil,nil,URLError(.badURL)); return }
        requestQueue.async {
            if pending[url] != nil { pending[url]?.append(completion); return }
            pending[url] = [completion]
            session.dataTask(with:request) { data,response,error in
                requestQueue.async {
                    let callbacks = pending.removeValue(forKey:url) ?? []
                    for callback in callbacks {
                        Self.renderQueue.addOperation { callback(data,response,error) }
                    }
                }
            }.resume()
        }
    }
    private static let renderQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "walking-map-image-processing"
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .userInitiated
        return queue
    }()
    private static let imageContext = CIContext(options:[.cacheIntermediates:false])
    private static let styledTiles: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.totalCostLimit = 12*1024*1024
        return cache
    }()
    private static func darkTile(_ data: Data, url: URL) -> CGImage? {
        if let cached = styledTiles.object(forKey:url as NSURL)?.cgImage { return cached }
        guard let image = CIImage(data:data) else { return nil }
        // Invert tile luminance into the reference's deep green palette.
        // Geometry and labels remain the provider's original map content.
        let tinted = image.applyingFilter("CIColorMatrix",parameters:[
            "inputRVector":CIVector(x:-0.2126*0.018,y:-0.7152*0.018,z:-0.0722*0.018,w:0),
            "inputGVector":CIVector(x:-0.2126*0.045,y:-0.7152*0.045,z:-0.0722*0.045,w:0),
            "inputBVector":CIVector(x:-0.2126*0.035,y:-0.7152*0.035,z:-0.0722*0.035,w:0),
            "inputBiasVector":CIVector(x:0.020,y:0.050,z:0.039,w:0)
        ])
        guard let result = imageContext.createCGImage(tinted,from:image.extent) else { return nil }
        styledTiles.setObject(UIImage(cgImage:result),forKey:url as NSURL,cost:result.bytesPerRow*result.height)
        return result
    }
    var onFailure: (() -> Void)?
    init(onFailure: @escaping () -> Void) {
        super.init(urlTemplate:"https://tile.openstreetmap.org/{z}/{x}/{y}.png")
        minimumZ = 0; maximumZ = 22
        tileSize = CGSize(width:256,height:256)
        canReplaceMapContent = false // Keep native map beneath tiles during loading/failure.
        self.onFailure = onFailure
    }
    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, (any Error)?) -> Void) {
        // OSM serves through z19. Magnify its existing tiles at closer zooms,
        // rather than requesting nonexistent z20–22 tiles.
        let extraZoom = max(0, path.z - 19)
        let factor = 1 << extraZoom
        var source = path
        source.z -= extraZoom; source.x /= factor; source.y /= factor
        let request = URLRequest(url:url(forTilePath:source),cachePolicy:.useProtocolCachePolicy)
        Self.load(request) { [weak self] data,response,error in
            if error == nil, let response = response as? HTTPURLResponse, response.statusCode == 200,
               response.mimeType == "image/png", let data, !data.isEmpty {
                guard let image = Self.darkTile(data,url:request.url!) else {
                    result(nil,URLError(.cannotDecodeContentData)); return
                }
                let size = CGFloat(image.width) / CGFloat(factor)
                let rect = CGRect(x:CGFloat(path.x % factor)*size,y:CGFloat(path.y % factor)*size,width:size,height:size)
                guard let cropped = image.cropping(to:rect) else {
                    result(nil,URLError(.cannotDecodeContentData)); return
                }
                // Always return the advertised 256×256 tile, even at z22.
                let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
                let enlarged = UIGraphicsImageRenderer(size:CGSize(width:256,height:256),format:format).image { context in
                    context.cgContext.interpolationQuality = .high
                    UIImage(cgImage:cropped).draw(in:CGRect(x:0,y:0,width:256,height:256))
                }
                result(enlarged.pngData(),nil)
            } else {
                result(nil,error ?? URLError(.badServerResponse))
                DispatchQueue.main.async { self?.onFailure?() }
            }
        }
    }
}

struct CampusMap: UIViewRepresentable {
    var region: MKCoordinateRegion?
    var cameraRevision: Int
    var style: String
    var reload: Int
    var selected: GeoPoint?
    var simulated: GeoPoint?
    var stops: [JourneyStop]
    var busStops: [JourneyStop]
    var legs: [JourneyLeg]
    var onTap: (GeoPoint) -> Void
    var onBusStop: (JourneyStop) -> Void
    var onRegion: (MKCoordinateRegion, Bool) -> Void
    var onTileFailure: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = false
        map.overrideUserInterfaceStyle = .dark
        map.backgroundColor = UIColor(GhostPalette.background)
        map.isScrollEnabled = true; map.isZoomEnabled = true; map.isRotateEnabled = true
        map.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance:45,maxCenterCoordinateDistance:40_000_000)
        map.showsCompass = true; map.showsScale = true
        map.accessibilityIdentifier = "journeyMap"
        let tap = UITapGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.didTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        // Let the native double-tap zoom recognizer win over pin placement.
        for recognizer in context.coordinator.recognizers(in:map) {
            if let doubleTap = recognizer as? UITapGestureRecognizer, doubleTap.numberOfTapsRequired > 1 {
                tap.require(toFail:doubleTap)
            }
        }
        map.addGestureRecognizer(tap)
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.update(map)
    }
    static func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) { map.delegate = nil }

    final class Pin: MKPointAnnotation {
        var kind = "stop"
        var busStop: JourneyStop?
        var number: Int?
    }
    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: CampusMap
        private var lastCameraRevision: Int?
        private var style = ""
        private var reload = -1
        private var tileLayer: WalkingMapTiles?
        private var pins: [Pin] = []
        private var selected: GeoPoint?
        private var simulated: GeoPoint?
        private var stops: [JourneyStop] = []
        private var buses: [JourneyStop] = []
        private var routePoints: [[GeoPoint]] = []
        private var routeLayers: [MKPolyline] = []
        private var applyingRegion = false
        private var userMoving = false
        private var reportedTileFailure = false
        init(_ parent: CampusMap) { self.parent = parent }
        func recognizers(in view: UIView) -> [UIGestureRecognizer] {
            (view.gestureRecognizers ?? []) + view.subviews.flatMap { recognizers(in:$0) }
        }
        func update(_ map: MKMapView) {
            if style != parent.style || reload != parent.reload {
                style = parent.style; reload = parent.reload; reportedTileFailure = false
                if let tileLayer { map.removeOverlay(tileLayer) }
                tileLayer = nil
                map.mapType = style == "Satellite" ? .satellite : .standard
                map.isPitchEnabled = style != "Walking"
                if style == "Walking" {
                    let tiles = WalkingMapTiles { [weak self] in
                        guard let self, self.style == "Walking", !self.reportedTileFailure else { return }
                        self.reportedTileFailure = true; self.parent.onTileFailure()
                    }
                    tileLayer = tiles; map.insertOverlay(tiles,at:0,level:.aboveLabels)
                }
            }
            if let region = parent.region, lastCameraRevision != parent.cameraRevision {
                lastCameraRevision = parent.cameraRevision; applyingRegion = true
                map.setRegion(region,animated:false)
                applyingRegion = false
            }
            if selected != parent.selected || simulated != parent.simulated || stops != parent.stops || buses != parent.busStops {
                selected = parent.selected; simulated = parent.simulated; stops = parent.stops; buses = parent.busStops
                map.removeAnnotations(pins); pins = []
                func add(_ point: GeoPoint, _ title: String, _ kind: String, number: Int? = nil, bus: JourneyStop? = nil) {
                    let pin = Pin(); pin.coordinate = point.coordinate; pin.title = title; pin.kind = kind; pin.number = number; pin.busStop = bus; pins.append(pin)
                }
                if let selected { add(selected,"Selected location","selected") }
                if let simulated { add(simulated,"Simulated location","simulated") }
                for (index,stop) in stops.enumerated() { add(stop.point,"\(index+1). \(stop.name)","stop",number:index+1) }
                for stop in buses { add(stop.point,stop.name,"bus",bus:stop) }
                map.addAnnotations(pins)
            }
            let points = parent.legs.map(\.points)
            if points != routePoints {
                routePoints = points
                map.removeOverlays(routeLayers)
                routeLayers = points.map { MKPolyline(coordinates:$0.map(\.coordinate),count:$0.count) }
                map.addOverlays(routeLayers,level:.aboveLabels)
            }
        }
        @objc func didTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let map = recognizer.view as? MKMapView else { return }
            parent.onTap(GeoPoint(map.convert(recognizer.location(in:map),toCoordinateFrom:map)))
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let candidate = view {
                if candidate is MKAnnotationView || candidate is UIControl { return false }
                view = candidate.superview
            }
            return true
        }
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            if !applyingRegion {
                userMoving = recognizers(in:mapView).contains { $0.state == .began || $0.state == .changed }
            }
        }
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let moved = userMoving; userMoving = false
            let region = mapView.region
            // Do not convert a user pan into a new programmatic camera command.
            DispatchQueue.main.async { [weak self] in self?.parent.onRegion(region,moved) }
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay { return MKTileOverlayRenderer(tileOverlay:tile) }
            if let line = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline:line)
                renderer.strokeColor = UIColor(GhostPalette.accent); renderer.lineWidth = 6; renderer.lineCap = .round; renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay:overlay)
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? Pin else { return nil }
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier:"ghostPin") as? MKMarkerAnnotationView) ?? MKMarkerAnnotationView(annotation:pin,reuseIdentifier:"ghostPin")
            view.annotation = pin; view.canShowCallout = true
            view.markerTintColor = pin.number == 1 || pin.kind == "selected"
                ? UIColor(red:0.88,green:0.43,blue:0.30,alpha:1)
                : UIColor(red:0.13,green:0.43,blue:0.37,alpha:1)
            view.glyphTintColor = .white
            view.glyphText = pin.number.map(String.init)
            view.glyphImage = pin.number == nil ? UIImage(systemName:pin.kind == "bus" ? "bus.fill" : pin.kind == "simulated" ? "location.fill" : "mappin") : nil
            view.displayPriority = pin.number == nil ? .defaultHigh : .required
            return view
        }
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let stop = (view.annotation as? Pin)?.busStop { parent.onBusStop(stop) }
        }
    }
}
