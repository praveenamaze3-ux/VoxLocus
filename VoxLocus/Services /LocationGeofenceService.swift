import CoreLocation
import MapKit
import Combine

@MainActor
final class LocationGeofenceService: NSObject, ObservableObject, CLLocationManagerDelegate {

    @Published var currentLocation: CLLocation?
    @Published var suggestedNoteIDs: [UUID] = []
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var locationError: String?

    /// How close (meters) a note must be to appear as "nearby".
    let nearbyRadiusMeters: CLLocationDistance = 300

    private let manager = CLLocationManager()
    private let geofenceRadius: CLLocationDistance = 150
    /// Stored coordinates for live distance-based nearby checks.
    private var registeredNoteCoordinates: [UUID: CLLocationCoordinate2D] = [:]

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 30
    }
    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdating()
        default:
            locationError = "Location access denied. Enable it in Settings."
        }
    }

    func startUpdating() {
        manager.startUpdatingLocation()
    }

    func registerGeofence(for note: NoteDTO) {
        guard note.latitude != 0 || note.longitude != 0 else { return }
        let coord = CLLocationCoordinate2D(latitude: note.latitude, longitude: note.longitude)

        // Store for distance-based nearby filter.
        registeredNoteCoordinates[note.id] = coord
        refreshNearbySuggestions()

        // Also register OS geofence for background entry events.
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        let region = CLCircularRegion(center: coord, radius: geofenceRadius, identifier: note.id.uuidString)
        region.notifyOnEntry = true
        region.notifyOnExit  = false
        manager.startMonitoring(for: region)
    }

    func removeGeofence(noteID: UUID) {
        registeredNoteCoordinates.removeValue(forKey: noteID)
        if let region = manager.monitoredRegions.first(where: { $0.identifier == noteID.uuidString }) {
            manager.stopMonitoring(for: region)
        }
        suggestedNoteIDs.removeAll { $0 == noteID }
    }

    // MARK: - Nearby check

    private func refreshNearbySuggestions() {
        guard let userLocation = currentLocation else { return }
        suggestedNoteIDs = registeredNoteCoordinates.compactMap { id, coord in
            let noteLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            return userLocation.distance(from: noteLocation) <= nearbyRadiusMeters ? id : nil
        }
    }

    // MARK: - Reverse geocoding (iOS 26 MapKit API)

    func currentPlaceName() async -> String? {
        guard let location = currentLocation else { return nil }
        // MKReverseGeocodingRequest replaces deprecated CLGeocoder (iOS 26).
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        do {
            let mapItems = try await request.mapItems
            guard let item = mapItems.first else { return nil }
            if let short = item.address?.shortAddress, !short.isEmpty { return short }
            return item.name
        } catch {
            return nil
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.startUpdating()
                self.locationError = nil
            case .denied, .restricted:
                self.locationError = "Location access denied. Enable it in Settings."
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Pick the most accurate fix (lowest horizontalAccuracy, must be ≥ 0).
        guard let best = locations.filter({ $0.horizontalAccuracy >= 0 })
                                  .min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy })
        else { return }
        Task { @MainActor in
            self.currentLocation = best
            self.refreshNearbySuggestions()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let uuid = UUID(uuidString: region.identifier) else { return }
        Task { @MainActor in
            if !self.suggestedNoteIDs.contains(uuid) { self.suggestedNoteIDs.append(uuid) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.locationError = error.localizedDescription }
        print("⚠️ Location error: \(error)")
    }
}

