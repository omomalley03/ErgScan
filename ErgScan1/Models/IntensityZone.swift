//
//  IntensityZone.swift
//  ErgScan1
//
//  Created by Claude on 2/10/26.
//

import SwiftUI

enum IntensityZone: String, CaseIterable, Codable {
    case ut2 = "UT2"
    case ut1 = "UT1"
    case at = "AT"
    case max = "Max"

    var displayName: String { rawValue }

    var fullName: String {
        switch self {
        case .ut2: return "Utilization Training 2"
        case .ut1: return "Utilization Training 1"
        case .at: return "Anaerobic Threshold"
        case .max: return "Maximum Effort"
        }
    }

    var color: Color {
        switch self {
        case .ut2: return .blue
        case .ut1: return .green
        case .at: return .yellow
        case .max: return .red
        }
    }
}
