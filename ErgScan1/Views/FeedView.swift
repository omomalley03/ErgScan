//
//  FeedView.swift
//  ErgScan1
//
//  Created by Claude on 2/10/26.
//

import SwiftUI

struct FeedView: View {
    @Binding var showSearch: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)

                    Text("Activity Feed")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("See what your team is up to")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Text("Coming Soon")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 20)
                }
                .padding(.bottom, 80)
            }
            .navigationTitle("Feed")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
        }
    }
}
