//
//  TeamsView.swift
//  ErgScan1
//
//  Created by Claude on 2/10/26.
//

import SwiftUI

struct TeamsView: View {
    @Binding var showSearch: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)

                    Text("Teams")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Connect with your rowing club and teammates")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Text("Coming Soon")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 20)
                }
                .padding()
            }
            .navigationTitle("Teams")
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
