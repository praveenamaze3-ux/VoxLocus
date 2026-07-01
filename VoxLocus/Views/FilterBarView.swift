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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(title: "All", isSelected: selectedCategory == nil) {
                        selectedCategory = nil
                    }
                    ForEach(NoteCategory.allCases) { category in
                        chip(title: category.rawValue, systemImage: category.systemImage, isSelected: selectedCategory == category) {
                            selectedCategory = (selectedCategory == category) ? nil : category
                        }
                    }
                }
                .padding(.horizontal)
            }

            HStack(spacing: 16) {
                Toggle(isOn: $showOnlyWithTodos) {
                    Label("Has To-Dos", systemImage: "checklist")
                }
                .toggleStyle(.button)
                .font(.caption)

                Toggle(isOn: $showOnlyNearby) {
                    Label("Nearby", systemImage: "location.fill")
                }
                .toggleStyle(.button)
                .font(.caption)

                Spacer()
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 6)
    }

    private func chip(title: String, systemImage: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.caption.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color(.systemGray5))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
    }
}

#Preview {
    FilterBarView(selectedCategory: .constant(nil), showOnlyWithTodos: .constant(false), showOnlyNearby: .constant(false))
}
