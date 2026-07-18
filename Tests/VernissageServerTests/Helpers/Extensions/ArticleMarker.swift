//
//  https://mczachurski.dev
//  Copyright © 2026 Marcin Czachurski and the repository contributors.
//  Licensed under the Apache License 2.0.
//

@testable import VernissageServer
import Fluent
import Vapor

extension Application {
    func createArticleMarker(user: User, article: Article) async throws -> ArticleMarker {
        let id = await ApplicationManager.shared.generateId()
        let articleMarker = try ArticleMarker(id: id, articleId: article.requireID(), userId: user.requireID())
        try await articleMarker.save(on: self.db)
        return articleMarker
    }

    func getArticleMarker(user: User) async throws -> ArticleMarker? {
        return try await ArticleMarker.query(on: self.db)
            .filter(\.$user.$id == user.requireID())
            .with(\.$article)
            .first()
    }
}
