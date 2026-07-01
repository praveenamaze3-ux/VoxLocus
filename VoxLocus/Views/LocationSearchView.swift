//
//  LocationSearchView.swift
//  VoxLocus
//
//  Created by Praveen V on 01/07/26.
//
//
//  LocationSearchView.swift
//  SmartNotes
//
//
//  LocationSearchView.swift
//  SmartNotes
//
//
//  LocationSearchView.swift
//  SmartNotes
//
//
//  LocationSearchView.swift
//  SmartNotes
//
//  iOS 26+: Uses MKReverseGeocodingRequest + MKAddress (fullAddress / shortAddress)
//           and MKAddressRepresentations for formatted strings.
//  iOS 25 and below: Falls back to CLGeocoder + MKPlacemark.
//
//
//  LocationSearchView.swift
//  SmartNotes
//
//  iOS 26+: Uses MKReverseGeocodingRequest + MKAddress (fullAddress / shortAddress)
//           and MKAddressRepresentations for formatted strings.
//  iOS 25 and below: Falls back to CLGeocoder + MKPlacemark.
//
//
//  LocationSearchView.swift
//  SmartNotes
//
//  iOS 26+: Uses MKReverseGeocodingRequest + MKAddress (fullAddress / shortAddress)
//           and MKAddressRepresentations for formatted strings.
//  iOS 25 and below: Falls back to CLGeocoder + MKPlacemark.
//

import SwiftUI
import MapKit
import Combine

// MARK: - Result model

struct LocationResult: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D

    var displayTitle: String {
        subtitle.isEmpty ? name : "\(name), \(subtitle)"
    }

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

            isSearching = true
            errorMessage = nil

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = q
            // No region set — results are driven purely by the user's
            // typed query, not biased toward device location.
            request.resultTypes = [.pointOfInterest, .address]

            do {
                let response = try await MKLocalSearch(request: request).start()
                guard !Task.isCancelled else { return }

                results = response.mapItems.map { item in
                    subtitleForItem(item, name: item.name ?? "Unknown")
                }
            } catch {
                guard !Task.isCancelled else { return }
                if (error as NSError).code != NSURLErrorCancelled {
                    errorMessage = "Search failed. Try again."
                }
            }
            isSearching = false
        }
    }

    private func subtitleForItem(_ item: MKMapItem, name: String) -> LocationResult {

        if #available(iOS 26.0, *) {
            let coordinate = item.location.coordinate
            // Use fullAddress so the user can clearly confirm which
            // specific place they're selecting (city, country etc.)
            let subtitle   = item.address?.fullAddress
                          ?? item.address?.shortAddress
                          ?? ""
            return LocationResult(name: name, subtitle: subtitle, coordinate: coordinate)
        } else {
            // Pre-iOS 26: CLPlacemark fields, no placemark.coordinate needed.
            let coordinate = CLLocationCoordinate2D(
                latitude:  item.placemark.location?.coordinate.latitude  ?? 0,
                longitude: item.placemark.location?.coordinate.longitude ?? 0
            )
            let parts = [item.placemark.locality,
                         item.placemark.administrativeArea]
                .compactMap { $0 }.filter { !$0.isEmpty }
            return LocationResult(name: name,
                                  subtitle: parts.joined(separator: ", "),
                                  coordinate: coordinate)
        }
    }

    func clear() {
        searchTask?.cancel()
        query = ""; results = []; errorMessage = nil
    }
}

// MARK: - Sheet View

struct LocationSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = LocationSearchViewModel()
    @EnvironmentObject var locationService: LocationGeofenceService

    let onSelect: (LocationResult) -> Void

    var body: some View {
        NavigationStack {
            List {
                // "Use my current location" shortcut
                if locationService.currentLocation != nil {
                    Button { useCurrentLocation() } label: {
                        Label("Use My Current Location", systemImage: "location.fill")
                            .foregroundStyle(.blue)
                    }
                }

                if vm.isSearching {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Searching…").foregroundStyle(.secondary)
                    }
                } else if vm.results.isEmpty && !vm.query.isEmpty {
                    Text("No results for \"\(vm.query)\"")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(vm.results) { result in
                        Button {
                            onSelect(result)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(result.name)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if let err = vm.errorMessage {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Add Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { vm.clear(); dismiss() }
                }
            }
            .searchable(
                text: $vm.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search for a place…"
            )
            .onChange(of: vm.query) { _, _ in vm.search() }
        }
    }

    // MARK: - Current location

    private func useCurrentLocation() {
        guard let location = locationService.currentLocation else { return }
        Task {
            if #available(iOS 26.0, *) {
                // MKReverseGeocodingRequest is the iOS 26 replacement for CLGeocoder.
                guard let request = MKReverseGeocodingRequest(location: location) else { return }
                guard let item = try? await request.mapItems.first else { return }
                let name     = item.name ?? "Current Location"
                let subtitle = item.address?.shortAddress
                            ?? item.address?.fullAddress
                            ?? ""
                let coord    = item.location.coordinate
                onSelect(LocationResult(name: name, subtitle: subtitle, coordinate: coord))
            } else {
                // Pre-iOS 26 fallback.
                let geocoder = CLGeocoder()
                guard let placemark = try? await geocoder
                    .reverseGeocodeLocation(location).first else { return }
                let parts = [placemark.locality, placemark.administrativeArea]
                    .compactMap { $0 }.filter { !$0.isEmpty }
                onSelect(LocationResult(
                    name: placemark.name ?? "Current Location",
                    subtitle: parts.joined(separator: ", "),
                    coordinate: location.coordinate
                ))
            }
            dismiss()
        }
    }
}
