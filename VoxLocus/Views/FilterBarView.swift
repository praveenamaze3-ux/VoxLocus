//
//  FilterBarView.swift
//  VoxLocus
//
//  Created by Praveen V on 30/06/26.
//
import SwiftUI

struct FilterBarView: View {
    @Binding var selectedCategory: NoteCategory?
    @Binding var showOnlyWithTodos: Bool
    @Binding var showOnlyNearby: Bool

    var body: some View {
        VStack(spacing: 8) {
            // Category chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(title: "All", icon: "tray.fill",
                         color: AppTheme.accent,
                         isSelected: selectedCategory == nil) {
                        selectedCategory = nil
                    }
                    ForEach(NoteCategory.allCases) { cat in
                        let color = AppTheme.categoryColor(for: cat.rawValue)
                        chip(title: cat.rawValue, icon: cat.systemImage,
                             color: color,
                             isSelected: selectedCategory == cat) {
                            selectedCategory = (selectedCategory == cat) ? nil : cat
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }

            // General filter toggles
            HStack(spacing: 10) {
                filterToggle(label: "Has To-Dos", icon: "checklist",
                             isOn: $showOnlyWithTodos, color: AppTheme.success)
                filterToggle(label: "Nearby", icon: "location.fill",
                             isOn: $showOnlyNearby, color: AppTheme.saveAmber)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
        .background(Color(hex: "#0A0C24"))
    }

    private func chip(title: String, icon: String, color: Color,
                      isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2)
                Text(title).font(.caption.bold())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                isSelected ? color : AppTheme.surface,
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(
                isSelected ? color : AppTheme.border, lineWidth: 1)
            )
            .foregroundStyle(isSelected ? .white : AppTheme.textSecondary)
        }
    }

    private func filterToggle(label: String, icon: String,
                               isOn: Binding<Bool>, color: Color) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2)
                Text(label).font(.caption.bold())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isOn.wrappedValue ? color.opacity(0.2) : AppTheme.surface,
                        in: Capsule())
            .overlay(Capsule().strokeBorder(
                isOn.wrappedValue ? color : AppTheme.border, lineWidth: 1)
            )
            .foregroundStyle(isOn.wrappedValue ? color : AppTheme.textSecondary)
        }
    }
}
