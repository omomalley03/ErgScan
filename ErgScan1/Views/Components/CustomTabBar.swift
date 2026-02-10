//
//  CustomTabBar.swift
//  ErgScan1
//
//  Created by Claude on 2/10/26.
//

import SwiftUI

struct CustomTabBar: View {
    @Binding var selectedTab: TabItem
    let onCenterButtonTap: () -> Void
    @EnvironmentObject var themeViewModel: ThemeViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Dashboard
                TabBarButton(tab: .dashboard, selectedTab: $selectedTab)

                // Log
                TabBarButton(tab: .log, selectedTab: $selectedTab)

                // Center button (custom styled)
                CenterAddButton(action: onCenterButtonTap)
                    .padding(.horizontal, 20)

                // Teams
                TabBarButton(tab: .teams, selectedTab: $selectedTab)

                // Profile
                TabBarButton(tab: .profile, selectedTab: $selectedTab)
            }
            .frame(height: 50)
            .background(
                Color(.systemBackground)
                    .shadow(color: .black.opacity(0.1), radius: 5, y: -2)
            )
        }
        .background(Color(.systemBackground))
    }
}

private struct TabBarButton: View {
    let tab: TabItem
    @Binding var selectedTab: TabItem

    var body: some View {
        Button {
            HapticService.shared.lightImpact()
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: selectedTab == tab ? tab.icon : tab.unselectedIcon)
                    .font(.system(size: 24))
                Text(tab.title)
                    .font(.caption2)
            }
            .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct CenterAddButton: View {
    let action: () -> Void
    @EnvironmentObject var themeViewModel: ThemeViewModel
    @Environment(\.colorScheme) var systemColorScheme

    var body: some View {
        Button(action: {
            HapticService.shared.lightImpact()
            action()
        }) {
            ZStack {
                Circle()
                    .fill(centerButtonBackgroundColor)
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(centerButtonForegroundColor)
            }
        }
        .offset(y: -10)
    }

    private var centerButtonBackgroundColor: Color {
        switch themeViewModel.currentTheme {
        case .light:
            return .black
        case .dark:
            return Color(.systemGray6)
        case .system:
            return systemColorScheme == .dark ? Color(.systemGray6) : .black
        }
    }

    private var centerButtonForegroundColor: Color {
        switch themeViewModel.currentTheme {
        case .light:
            return .white
        case .dark:
            return .black
        case .system:
            return systemColorScheme == .dark ? .black : .white
        }
    }
}

#Preview("Light Mode") {
    @Previewable @State var selectedTab: TabItem = .dashboard

    VStack {
        Spacer()
        CustomTabBar(
            selectedTab: $selectedTab,
            onCenterButtonTap: { print("Center tapped") }
        )
        .environmentObject(ThemeViewModel())
    }
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    @Previewable @State var selectedTab: TabItem = .dashboard

    VStack {
        Spacer()
        CustomTabBar(
            selectedTab: $selectedTab,
            onCenterButtonTap: { print("Center tapped") }
        )
        .environmentObject(ThemeViewModel())
    }
    .preferredColorScheme(.dark)
}
