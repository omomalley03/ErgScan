import Foundation

enum UserRole: String, CaseIterable, Identifiable, Codable {
    case rower = "rower"
    case coxswain = "coxswain"
    case coach = "coach"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rower: return "Rower"
        case .coxswain: return "Coxswain"
        case .coach: return "Coach"
        }
    }

    var icon: String {
        switch self {
        case .rower: return "figure.rowing"
        case .coxswain: return "megaphone.fill"
        case .coach: return "clipboard.fill"
        }
    }

    var description: String {
        switch self {
        case .rower: return "I erg and submit workouts to the team"
        case .coxswain: return "I log ergs on behalf of rowers"
        case .coach: return "I coach the team and assign workouts"
        }
    }

    // MARK: - CSV Helpers (for multi-role storage)

    static func fromCSV(_ csv: String) -> [UserRole] {
        csv.split(separator: ",")
            .compactMap { UserRole(rawValue: String($0).trimmingCharacters(in: .whitespaces)) }
    }

    static func toCSV(_ roles: [UserRole]) -> String {
        roles.map(\.rawValue).joined(separator: ",")
    }

    static func toCSV(_ roles: Set<UserRole>) -> String {
        toCSV(Array(roles).sorted { $0.rawValue < $1.rawValue })
    }
}
