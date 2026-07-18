//
//  https://mczachurski.dev
//  Copyright © 2026 Marcin Czachurski and the repository contributors.
//  Licensed under the Apache License 2.0.
//

import Fluent
import Vapor

/// Last article read by user.
final class ArticleMarker: Model, @unchecked Sendable {
    static let schema: String = "ArticleMarkers"

    @ID(custom: .id, generatedBy: .user)
    var id: Int64?

    @Parent(key: "articleId")
    var article: Article

    @Parent(key: "userId")
    var user: User

    @Timestamp(key: "createdAt", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updatedAt", on: .update)
    var updatedAt: Date?

    init() { }

    convenience init(id: Int64, articleId: Int64, userId: Int64) {
        self.init()

        self.id = id
        self.$article.id = articleId
        self.$user.id = userId
    }
}

/// Allows `ArticleMarker` to be encoded to and decoded from HTTP messages.
extension ArticleMarker: Content { }
