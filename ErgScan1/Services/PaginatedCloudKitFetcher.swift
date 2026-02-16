import Foundation
import CloudKit

@MainActor
class PaginatedCloudKitFetcher {

    struct Page {
        let records: [CKRecord]
        let hasMore: Bool
    }

    private let database: CKDatabase
    private var currentCursor: CKQueryOperation.Cursor?
    let pageSize: Int

    init(database: CKDatabase, pageSize: Int = 20) {
        self.database = database
        self.pageSize = pageSize
    }

    func fetchFirstPage(query: CKQuery) async throws -> Page {
        currentCursor = nil
        let (matchResults, cursor) = try await database.records(matching: query, resultsLimit: pageSize)
        currentCursor = cursor

        let records = matchResults.compactMap { (_, result) -> CKRecord? in
            guard case .success(let record) = result else { return nil }
            return record
        }

        return Page(records: records, hasMore: cursor != nil)
    }

    func fetchNextPage() async throws -> Page? {
        guard let cursor = currentCursor else { return nil }
        let (matchResults, nextCursor) = try await database.records(continuingMatchFrom: cursor, resultsLimit: pageSize)
        currentCursor = nextCursor

        let records = matchResults.compactMap { (_, result) -> CKRecord? in
            guard case .success(let record) = result else { return nil }
            return record
        }

        return Page(records: records, hasMore: nextCursor != nil)
    }

    var hasMorePages: Bool {
        currentCursor != nil
    }
}
