//
//  TabItem.swift
//  ErgScan1
//
//  Created by Claude on 2/10/26.
//

import Foundation

enum TabItem: Int, CaseIterable {
    case dashboard = 0
    case log = 1
    case add = 2  // Center button (not a real tab)
    case teams = 3
    case profile = 4

    var title: String {
        switch self {
        case .dashboard:
            return "Dashboard"
        case .log:
            return "Log"
        case .add:
            return ""
        case .teams:
            return "Friends"
        case .profile:
            return "Profile"
        }
    }

    var icon: String {
        switch self {
        case .dashboard:
            return "house.fill"
        case .log:
            return "clipboard.fill"
        case .add:
            return "plus"
        case .teams:
            return "person.2.fill"
        case .profile:
            return "person.circle.fill"
        }
    }

    var unselectedIcon: String {
        switch self {
        case .dashboard:
            return "house"
        case .log:
            return "clipboard"
        case .add:
            return "plus"
        case .teams:
            return "person.2"
        case .profile:
            return "person.circle"
        }
    }
}
