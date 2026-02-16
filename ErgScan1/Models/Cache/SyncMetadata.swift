import Foundation
import SwiftData

@Model
final class SyncMetadata {
    @Attribute(.unique) var category: String
    var lastSyncedAt: Date

    init(category: String, lastSyncedAt: Date = .distantPast) {
        self.category = category
        self.lastSyncedAt = lastSyncedAt
    }
}
