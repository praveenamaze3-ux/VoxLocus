import SwiftUI
import MapKit

struct LocationSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = LocationSearchViewModel()
    @EnvironmentObject var locationService: LocationGeofenceService
    let onSelect: (LocationResult) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                VStack(spacing: 0) {
                    if locationService.currentLocation != nil {
                        currentLocationRow
                    }
                    resultsContent
                    if let err = vm.errorMessage {
                        Text(err).font(.caption)
                            .foregroundStyle(AppTheme.recordingRed)
                            .padding()
                    }
                }
            }
            .navigationTitle("Add Location")
            .compactDarkNavBar()
            .toolbar {
                cancelToolbarItem { vm.clear(); dismiss() }
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
            guard let result = await vm.resolveCurrentLocation(location) else { return }
            onSelect(result)
            dismiss()
        }
    }

    // MARK: - Current location shortcut

    private var currentLocationRow: some View {
        LocationResultRow(
            iconName: "location.fill",
            iconTint: AppTheme.accent,
            title: String(localized: "Use My Current Location"),
            titleColor: AppTheme.accent,
            subtitle: "",
            action: useCurrentLocation
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsContent: some View {
        if vm.isSearching {
            searchingState
        } else if vm.results.isEmpty && !vm.query.isEmpty {
            noResultsState
        } else {
            resultsList
        }
    }

    private var searchingState: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                ProgressView().tint(AppTheme.accent)
                Text("Searching…")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
        }
    }

    private var noResultsState: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "mappin.slash")
                    .font(.system(size: 36))
                    .foregroundStyle(AppTheme.textSecondary)
                Text("No results for \"\(vm.query)\"")
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(vm.results) { result in
                    LocationResultRow(
                        iconName: "mappin.fill",
                        iconTint: AppTheme.recordingRed,
                        title: result.name,
                        titleColor: AppTheme.textPrimary,
                        subtitle: result.subtitle
                    ) {
                        onSelect(result); dismiss()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }
}
