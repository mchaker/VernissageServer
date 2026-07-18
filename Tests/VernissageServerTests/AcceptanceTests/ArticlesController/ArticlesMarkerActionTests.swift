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

    @Suite("Articles (POST /articles/marker/:id)", .serialized, .tags(.articles))
    struct ArticlesMarkerActionTests {
        var application: Application!

        init() async throws {
            self.application = try await ApplicationManager.shared.application()
        }

        @Test
        func `Marker should be created for authorized user and sign in news article`() async throws {
            // Arrange.
            let reader = try await application.createUser(userName: "articlesmarkerreader")
            let author = try await application.createUser(userName: "articlesmarkerauthor")
            let article = try await application.createArticle(
                userId: author.requireID(),
                title: "News article",
                body: "News body",
                visibility: .signInNews
            )

            // Act.
            let response = try await application.sendRequest(
                as: .user(userName: "articlesmarkerreader", password: "p@ssword"),
                to: "/articles/marker/\(article.stringId() ?? "")",
                method: .POST
            )

            // Assert.
            #expect(response.status == .ok, "Response HTTP status code should be ok (200).")
            let articleMarker = try #require(await application.getArticleMarker(user: reader))
            #expect(articleMarker.$article.id == article.id, "Correct article marker should be saved.")
        }

        @Test
        func `Existing marker should be updated`() async throws {
            // Arrange.
            let reader = try await application.createUser(userName: "articlesmarkerupdate")
            let author = try await application.createUser(userName: "articlesmarkerupauthor")
            let firstArticle = try await application.createArticle(
                userId: author.requireID(),
                title: "First news article",
                body: "First news body",
                visibility: .signInNews
            )
            let secondArticle = try await application.createArticle(
                userId: author.requireID(),
                title: "Second news article",
                body: "Second news body",
                visibility: .signInNews
            )
            let originalMarker = try await application.createArticleMarker(user: reader, article: firstArticle)

            // Act.
            let response = try await application.sendRequest(
                as: .user(userName: "articlesmarkerupdate", password: "p@ssword"),
                to: "/articles/marker/\(secondArticle.stringId() ?? "")",
                method: .POST
            )

            // Assert.
            #expect(response.status == .ok, "Response HTTP status code should be ok (200).")
            let articleMarker = try #require(await application.getArticleMarker(user: reader))
            #expect(articleMarker.id == originalMarker.id, "Existing marker should be updated instead of creating a new one.")
            #expect(articleMarker.$article.id == secondArticle.id, "Marker should point at the selected article.")
        }

        @Test
        func `Marker should not be saved for article outside sign in news`() async throws {
            // Arrange.
            let reader = try await application.createUser(userName: "articlesmarkervisible")
            let author = try await application.createUser(userName: "articlesmarkervisauth")
            let article = try await application.createArticle(
                userId: author.requireID(),
                title: "Home article",
                body: "Home body",
                visibility: .signInHome
            )

            // Act.
            let response = try await application.sendRequest(
                as: .user(userName: "articlesmarkervisible", password: "p@ssword"),
                to: "/articles/marker/\(article.stringId() ?? "")",
                method: .POST
            )

            // Assert.
            #expect(response.status == .notFound, "Response HTTP status code should be not found (404).")
            let articleMarker = try await application.getArticleMarker(user: reader)
            #expect(articleMarker == nil, "Marker should not be created for an article outside sign-in news.")
        }

        @Test
        func `Marker should not be updated for unauthorized user`() async throws {
            // Act.
            let response = try await application.sendRequest(
                to: "/articles/marker/63363",
                method: .POST
            )

            // Assert.
            #expect(response.status == .unauthorized, "Response HTTP status code should be unauthorized (401).")
        }
    }
}
