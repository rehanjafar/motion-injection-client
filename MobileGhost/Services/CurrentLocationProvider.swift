import CoreLocation

/// A cancellable foreground lookup for the opening camera. No user marker,
/// persistent tracking, or change to the simulation session.
final class CurrentLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum LocateError: Error { case denied, unavailable }
    @Published private(set) var isLocating = false
    private var manager: CLLocationManager?
    private var completion: ((Result<CLLocationCoordinate2D, LocateError>) -> Void)?
    private var timeout: DispatchWorkItem?
    private var retry: DispatchWorkItem?
    private var attempts = 0

    func locate(_ completion: @escaping (Result<CLLocationCoordinate2D, LocateError>) -> Void) {
        cancel()
        let manager = CLLocationManager()
        self.manager = manager
        self.completion = completion
        isLocating = true; attempts = 0
        manager.desiredAccuracy = 50
        manager.delegate = self
        checkAuthorization(manager)
    }
    func cancel() {
        timeout?.cancel(); timeout = nil
        retry?.cancel(); retry = nil
        manager?.delegate = nil
        manager?.stopUpdatingLocation()
        manager = nil; completion = nil; isLocating = false
    }
    private func checkAuthorization(_ manager: CLLocationManager) {
        guard manager === self.manager, isLocating else { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: finish(.failure(.denied))
        case .authorizedAlways, .authorizedWhenInUse:
            guard timeout == nil else { return }
            let work = DispatchWorkItem { [weak self, weak manager] in
                guard let self, let manager, manager === self.manager else { return }
                self.finish(.failure(.unavailable))
            }
            timeout = work
            DispatchQueue.main.asyncAfter(deadline:.now()+15,execute:work)
            requestFix(manager)
        @unknown default: finish(.failure(.unavailable))
        }
    }
    private func requestFix(_ manager: CLLocationManager) {
        guard manager === self.manager else { return }
        attempts += 1
        manager.requestLocation()
    }
    private func retryFix(_ manager: CLLocationManager) {
        guard attempts < 4 else { finish(.failure(.unavailable)); return }
        retry?.cancel()
        let work = DispatchWorkItem { [weak self, weak manager] in
            guard let self, let manager else { return }
            self.requestFix(manager)
        }
        retry = work
        DispatchQueue.main.asyncAfter(deadline:.now()+1,execute:work)
    }
    private func finish(_ result: Result<CLLocationCoordinate2D, LocateError>) {
        let callback = completion
        cancel()
        callback?(result)
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { checkAuthorization(manager) }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard manager === self.manager, isLocating else { return }
        let now = Date()
        guard let fix = locations.last(where: {
            CLLocationCoordinate2DIsValid($0.coordinate) && $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 1000 &&
            abs($0.timestamp.timeIntervalSince(now)) <= 30
        }) else { retryFix(manager); return }
        finish(.success(fix.coordinate))
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard manager === self.manager, isLocating else { return }
        if (error as? CLError)?.code == .denied { finish(.failure(.denied)) }
        else { retryFix(manager) }
    }
}
