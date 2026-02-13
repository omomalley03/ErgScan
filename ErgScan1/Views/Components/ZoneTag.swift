import SwiftUI

struct ZoneTag: View {
    let zone: IntensityZone

    var body: some View {
        Text(zone.displayName)
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(zone.color.opacity(0.2)))
            .foregroundColor(zone.color)
    }
}
