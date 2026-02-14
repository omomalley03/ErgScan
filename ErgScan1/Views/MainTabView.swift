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
    @State private var showGoals = false
    @State private var logHighlightDate: Date?
    @EnvironmentObject var themeViewModel: ThemeViewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab content
            Group {
                switch selectedTab {
                case .dashboard:
                    DashboardView(showSearch: $showSearch, onViewDay: { date in
                        selectedTab = .log
                        // Delay so LogView mounts before the highlight fires
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            logHighlightDate = date
                        }
                    })
                case .log:
                    LogView(showSearch: $showSearch, highlightDate: $logHighlightDate)
                case .add:
                    EmptyView()  // Never shown (center button doesn't navigate)
                case .teams:
                    FriendsView(showSearch: $showSearch)
                case .profile:
                    ProfileView(showSearch: $showSearch)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CustomTabBar(
                    selectedTab: $selectedTab,
                    onCenterButtonTap: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showAddSheet = true
                        }
                    }
                )
                .environmentObject(themeViewModel)
            }

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
                },
                onGoals: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showGoals = true
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
        .sheet(isPresented: $showGoals) {
            GoalsView()
        }
        .preferredColorScheme(themeViewModel.colorScheme)
    }
}
