import SwiftUI
import MapKit

/// Card showing a note's attached location: name/subtitle, a small
/// non-interactive map preview, a way to remove it, and a way to change it.
/// Used by both the add- and edit-note forms.
struct SelectedLocationCard: View {
    let location: LocationResult
    let onRemove: () -> Void
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(AppTheme.recordingRed)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.name)
                        .font(.body.bold())
                        .foregroundStyle(AppTheme.textPrimary)
                    if !location.subtitle.isEmpty {
                        Text(location.subtitle)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            Map(position: .constant(.region(MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )))) {
                Marker(location.name, coordinate: location.coordinate)
                    .tint(AppTheme.recordingRed)
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(true)

            Button("Change Location", action: onChange)
                .font(.subheadline)
                .foregroundStyle(AppTheme.accent)
        }
    }
}

/// Full-width button that opens location search — shown when a note has no
/// attached location yet.
struct AddLocationButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Add Location")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.glass)
        .tint(AppTheme.accent)
    }
}

/// The full contents of a note form's "Location" section: either the
/// selected-location card, or the add-location button. `onPickLocation` is
/// called both to add a location for the first time and to change one that's
/// already set.
struct LocationSectionContent: View {
    @Binding var selectedLocation: LocationResult?
    let onPickLocation: () -> Void

    var body: some View {
        if let location = selectedLocation {
            SelectedLocationCard(
                location: location,
                onRemove: { selectedLocation = nil },
                onChange: onPickLocation
            )
        } else {
            AddLocationButton(action: onPickLocation)
        }
    }
}
