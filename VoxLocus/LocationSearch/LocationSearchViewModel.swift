import MapKit
import CoreLocation
import Combine

// MARK: - Result model

struct LocationResult: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
    var displayTitle: String { subtitle.isEmpty ? name : "\(name), \(subtitle)" }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: LocationResult, rhs: LocationResult) -> Bool { lhs.id == rhs.id }
}

// MARK: - ViewModel

/// Owns all state and business logic for `LocationSearchView`: debounced
/// place search and reverse geocoding of the user's current location. The
/// view only binds to this and renders.
@MainActor
final class LocationSearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [LocationResult] = []
    @Published var isSearching = false
    @Published var errorMessage: String?
    private var searchTask: Task<Void, Never>?
    init() {}

    func search() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { results = []; return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            isSearching = true; errorMessage = nil
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = q
            request.resultTypes = [.pointOfInterest, .address]
            do {
                let response = try await MKLocalSearch(request: request).start()
                guard !Task.isCancelled else { return }
                results = response.mapItems.map { subtitleForItem($0) }
            } catch {
                guard !Task.isCancelled else { return }
                if (error as NSError).code != NSURLErrorCancelled {
                    errorMessage = String(localized: "Search failed. Try again.")
                }
            }
            isSearching = false
        }
    }

    private func subtitleForItem(_ item: MKMapItem) -> LocationResult {
        let name = item.name ?? String(localized: "Unknown")
        if #available(iOS 26.0, *) {
            let coord    = item.location.coordinate
            let subtitle = item.address?.fullAddress ?? item.address?.shortAddress ?? ""
            return LocationResult(name: name, subtitle: subtitle, coordinate: coord)
        } else {
            let coord = CLLocationCoordinate2D(
                latitude:  item.placemark.location?.coordinate.latitude  ?? 0,
                longitude: item.placemark.location?.coordinate.longitude ?? 0)
            let parts = [item.placemark.locality, item.placemark.administrativeArea]
                .compactMap { $0 }.filter { !$0.isEmpty }
            return LocationResult(name: name, subtitle: parts.joined(separator: ", "), coordinate: coord)
        }
    }

    func clear() { searchTask?.cancel(); query = ""; results = []; errorMessage = nil }

    /// Reverse-geocodes the device's current location into a `LocationResult`
    /// for the "Use My Current Location" shortcut. Returns `nil` if lookup
    /// fails, so the caller can just ignore the tap rather than show an error.
    func resolveCurrentLocation(_ location: CLLocation) async -> LocationResult? {
        if #available(iOS 26.0, *) {
            guard let req = MKReverseGeocodingRequest(location: location),
                  let item = try? await req.mapItems.first else { return nil }
            let name     = item.name ?? String(localized: "Current Location")
            let subtitle = item.address?.fullAddress ?? item.address?.shortAddress ?? ""
            let coord    = item.location.coordinate
            return LocationResult(name: name, subtitle: subtitle, coordinate: coord)
        } else {
            let geocoder = CLGeocoder()
            guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else { return nil }
            let parts = [placemark.locality, placemark.administrativeArea]
                .compactMap { $0 }.filter { !$0.isEmpty }
            return LocationResult(name: placemark.name ?? String(localized: "Current Location"),
                                   subtitle: parts.joined(separator: ", "),
                                   coordinate: location.coordinate)
        }
    }
}
