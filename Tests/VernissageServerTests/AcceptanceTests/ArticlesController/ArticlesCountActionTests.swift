//
//  https://mczachurski.dev
//  Copyright © 2026 Marcin Czachurski and the repository contributors.
//  Licensed under the Apache License 2.0.
//

@testable import VernissageServer
import Fluent
import Testing
import Vapor

extension ControllersTests {

    @Suite("Articles (GET /articles/count)", .serialized, .tags(.articles))
    struct ArticlesCountActionTests {
        var application: Application!

        init() async throws {
            self.application = try await ApplicationManager.shared.application()
        }

        @Test
        func `Count should include only newer sign in news articles`() async throws {
            // Arrange.
            let reader = try await application.createUser(userName: "articlescountreader")
            let author = try await application.createUser(userName: "articlescountauthor")
            let markerArticle = try await application.createArticle(
                userId: author.requireID(),
                title: "Marker article",
                body: "Marker body",
                visibility: .signInNews
            )
            _ = try await application.createArticleMarker(user: reader, article: markerArticle)

            _ = try await application.createArticle(
                userId: author.requireID(),
                title: "New home article",
                body: "New home body",
                visibility: .signInHome
            )
            _ = try await application.createArticle(
                userId: author.requireID(),
                title: "New news article 1",
                body: "New news body 1",
                visibility: .signInNews
            )
            _ = try await application.createArticle(
                userId: author.requireID(),
                title: "New news article 2",
                body: "New news body 2",
                visibility: .signInNews
            )

            // Act.
            let articlesCount = try await application.getResponse(
                as: .user(userName: "articlescountreader", password: "p@ssword"),
                to: "/articles/count",
                method: .GET,
                decodeTo: ArticlesCountDto.self
            )

            // Assert.
            #expect(articlesCount.amount == 2, "Counter should return only newer sign-in news articles.")
            #expect(articlesCount.articleId == markerArticle.stringId(), "Response should contain the current marker article Id.")
        }

        @Test
        func `Count should be zero when marker does not exist`() async throws {
            // Arrange.
            _ = try await application.createUser(userName: "articlescountnomarker")

            // Act.
            let articlesCount = try await application.getResponse(
                as: .user(userName: "articlescountnomarker", password: "p@ssword"),
                to: "/articles/count",
                method: .GET,
                decodeTo: ArticlesCountDto.self
            )

            // Assert.
            #expect(articlesCount.amount == 0, "Counter should be zero when the user has no marker.")
            #expect(articlesCount.articleId == nil, "Marker article Id should be empty when the marker does not exist.")
        }

        @Test
        func `Count should not be returned for unauthorized user`() async throws {
            // Act.
            let response = try await application.sendRequest(
                to: "/articles/count",
                method: .GET
            )

            // Assert.
            #expect(response.status == .unauthorized, "Response HTTP status code should be unauthorized (401).")
        }
    }
}
