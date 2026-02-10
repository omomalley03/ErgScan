//
//  MainTabView.swift
//  ErgScan1
//
//  Created by Claude on 2/10/26.
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: TabItem = .dashboard
    @State private var showAddSheet = false
    @State private var showScanner = false
    @State private var showImagePicker = false
    @State private var showSearch = false
    @EnvironmentObject var themeViewModel: ThemeViewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab content
            Group {
                switch selectedTab {
                case .dashboard:
                    DashboardView(showSearch: $showSearch)
                case .log:
                    LogView(showSearch: $showSearch)
                case .add:
                    EmptyView()  // Never shown (center button doesn't navigate)
                case .teams:
                    TeamsView(showSearch: $showSearch)
                case .profile:
                    ProfileView(showSearch: $showSearch)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Custom tab bar overlay
            CustomTabBar(
                selectedTab: $selectedTab,
                onCenterButtonTap: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showAddSheet = true
                    }
                }
            )
            .environmentObject(themeViewModel)

            // Add workout bottom sheet
            AddWorkoutSheet(
                isPresented: $showAddSheet,
                onScan: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showScanner = true
                    }
                },
                onUpload: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showImagePicker = true
                    }
                }
            )
        }
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $showScanner) {
            NavigationStack {
                ScannerView()
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView { image in
                // Handle selected image
                // Future: Pass to ScannerViewModel for OCR processing
                print("Selected image: \(image.size)")
            }
        }
        .sheet(isPresented: $showSearch) {
            SearchView()
        }
        .preferredColorScheme(themeViewModel.colorScheme)
    }
}
