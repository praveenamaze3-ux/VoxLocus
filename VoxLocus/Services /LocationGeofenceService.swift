//
//  LocationGeofenceService.swift
//  VoxLocus
//
//  Created by Praveen V on 30/06/26.
//

import CoreLocation
import Combine
internal import CoreData

@MainActor
final class LocationGeofenceService: NSObject, ObservableObject, CLLocationManagerDelegate {

    @Published var currentLocation: CLLocation?
    @Published var suggestedNoteIDs: [UUID] = []
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private let geofenceRadius: CLLocationDistance = 150   // metres

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        manager.startUpdatingLocation()
    }

    /// Registers a 150 m circular geofence around a note's stored coordinate.
    /// Called only when the user has manually set a location on the note.
    func registerGeofence(for note: NoteDTO) {
        guard note.latitude != 0 || note.longitude != 0,
              CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self)
        else { return }

        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: note.latitude, longitude: note.longitude),
            radius: geofenceRadius,
            identifier: note.id.uuidString
        )
        region.notifyOnEntry = true
        region.notifyOnExit  = false
        manager.startMonitoring(for: region)
    }

    func removeGeofence(noteID: UUID) {
        if let region = manager.monitoredRegions
            .first(where: { $0.identifier == noteID.uuidString }) {
            manager.stopMonitoring(for: region)
        }
        suggestedNoteIDs.removeAll { $0 == noteID }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedAlways || status == .authorizedWhenInUse {
                self.startUpdating()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in self.currentLocation = last }
    }

    /// Fires when the device enters a region tied to a saved note.
    /// The note's ID is surfaced in `suggestedNoteIDs` so the UI can
    /// show the "You're nearby" banner and "Nearby" filter.
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didEnterRegion region: CLRegion) {
        guard let uuid = UUID(uuidString: region.identifier) else { return }
        Task { @MainActor in
            if !self.suggestedNoteIDs.contains(uuid) {
                self.suggestedNoteIDs.append(uuid)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        print("⚠️ Location error: \(error.localizedDescription)")
    }
}

