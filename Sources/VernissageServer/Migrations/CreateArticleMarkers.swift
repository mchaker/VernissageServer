//
//  https://mczachurski.dev
//  Copyright © 2026 Marcin Czachurski and the repository contributors.
//  Licensed under the Apache License 2.0.
//

import Vapor
import Fluent
import SQLKit

extension ArticleMarker {
    struct CreateArticleMarkers: AsyncMigration {
        func prepare(on database: Database) async throws {
            try await database
                .schema(ArticleMarker.schema)
                .field(.id, .int64, .identifier(auto: false))
                .field("articleId", .int64, .required, .references(Article.schema, "id"))
                .field("userId", .int64, .required, .references(User.schema, "id"))
                .field("createdAt", .datetime)
                .field("updatedAt", .datetime)
                .unique(on: "userId")
                .create()

            if let sqlDatabase = database as? SQLDatabase {
                try await sqlDatabase
                    .create(index: "\(ArticleMarker.schema)_userIdIndex")
                    .on(ArticleMarker.schema)
                    .column("userId")
                    .run()

                try await sqlDatabase
                    .create(index: "\(ArticleMarker.schema)_articleIdIndex")
                    .on(ArticleMarker.schema)
                    .column("articleId")
                    .run()
            }
        }

        func revert(on database: Database) async throws {
            try await database.schema(ArticleMarker.schema).delete()
        }
    }
}
