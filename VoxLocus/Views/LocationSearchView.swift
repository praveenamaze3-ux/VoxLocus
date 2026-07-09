import SwiftUI
import MapKit
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
                    errorMessage = "Search failed. Try again."
                }
            }
            isSearching = false
        }
    }

    private func subtitleForItem(_ item: MKMapItem) -> LocationResult {
        let name = item.name ?? "Unknown"
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
}

// MARK: - Sheet View

struct LocationSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = LocationSearchViewModel()
    @EnvironmentObject var locationService: LocationGeofenceService
    let onSelect: (LocationResult) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    // Current location shortcut
                    if locationService.currentLocation != nil {
                        Button { useCurrentLocation() } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(AppTheme.accent.opacity(0.15))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "location.fill")
                                        .foregroundStyle(AppTheme.accent)
                                        .font(.subheadline)
                                }
                                Text("Use My Current Location")
                                    .font(.body.bold())
                                    .foregroundStyle(AppTheme.accent)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .font(.caption)
                            }
                            .padding(14)
                            .themedCard()
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                        }
                        .buttonStyle(.plain)
                    }

                    // Results
                    if vm.isSearching {
                        Spacer()
                        VStack(spacing: 12) {
                            ProgressView().tint(AppTheme.accent)
                            Text("Searching…")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        Spacer()
                    } else if vm.results.isEmpty && !vm.query.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "mappin.slash")
                                .font(.system(size: 36))
                                .foregroundStyle(AppTheme.textSecondary)
                            Text("No results for \"\(vm.query)\"")
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(vm.results) { result in
                                    Button {
                                        onSelect(result); dismiss()
                                    } label: {
                                        HStack(spacing: 12) {
                                            ZStack {
                                                Circle()
                                                    .fill(AppTheme.recordingRed.opacity(0.15))
                                                    .frame(width: 36, height: 36)
                                                Image(systemName: "mappin.fill")
                                                    .foregroundStyle(AppTheme.recordingRed)
                                                    .font(.subheadline)
                                            }
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(result.name)
                                                    .font(.body.bold())
                                                    .foregroundStyle(AppTheme.textPrimary)
                                                if !result.subtitle.isEmpty {
                                                    Text(result.subtitle)
                                                        .font(.caption)
                                                        .foregroundStyle(AppTheme.textSecondary)
                                                        .lineLimit(2)
                                                }
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .foregroundStyle(AppTheme.textSecondary)
                                                .font(.caption)
                                        }
                                        .padding(14)
                                        .themedCard()
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                        }
                    }

                    if let err = vm.errorMessage {
                        Text(err).font(.caption)
                            .foregroundStyle(AppTheme.recordingRed)
                            .padding()
                    }
                }
            }
            .navigationTitle("Add Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { vm.clear(); dismiss() }
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .searchable(text: $vm.query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search for a place…")
            .onChange(of: vm.query) { _, _ in vm.search() }
        }
    }

    private func useCurrentLocation() {
        guard let location = locationService.currentLocation else { return }
        Task {
            if #available(iOS 26.0, *) {
                guard let req = MKReverseGeocodingRequest(location: location),
                      let item = try? await req.mapItems.first else { return }
                let name     = item.name ?? "Current Location"
                let subtitle = item.address?.fullAddress ?? item.address?.shortAddress ?? ""
                let coord    = item.location.coordinate
                onSelect(LocationResult(name: name, subtitle: subtitle, coordinate: coord))
            } else {
                let geocoder = CLGeocoder()
                guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else { return }
                let parts = [placemark.locality, placemark.administrativeArea]
                    .compactMap { $0 }.filter { !$0.isEmpty }
                onSelect(LocationResult(name: placemark.name ?? "Current Location",
                                        subtitle: parts.joined(separator: ", "),
                                        coordinate: location.coordinate))
            }
            dismiss()
        }
    }
}
