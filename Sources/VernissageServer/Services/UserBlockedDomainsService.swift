//
//  https://mczachurski.dev
//  Copyright © 2024 Marcin Czachurski and the repository contributors.
//  Licensed under the Apache License 2.0.
//

import Vapor
import Fluent
import ActivityPubKit

extension Application.Services {
    struct UserBlockedDomainsServiceKey: StorageKey {
        typealias Value = UserBlockedDomainsServiceType
    }

    var userBlockedDomainsService: UserBlockedDomainsServiceType {
        get {
            self.application.storage[UserBlockedDomainsServiceKey.self] ?? UserBlockedDomainsService()
        }
        nonmutating set {
            self.application.storage[UserBlockedDomainsServiceKey.self] = newValue
        }
    }
}

@_documentation(visibility: private)
protocol UserBlockedDomainsServiceType: Sendable {
    /// Checks whether the given domain (host from URL) is blocked by the user.
    /// - Parameters:
    ///   - userId: Signed in user.
    ///   - url: The URL whose domain is checked against the block list.
    ///   - database: Database to perform the query on.
    /// - Returns: True if the domain is blocked by the user.
    /// - Throws: Database errors.
    func exists(userId: Int64, url: URL, on database: Database) async throws -> Bool

    /// Checks if the domain of the actor ID is blocked by the user.
    ///
    /// - Parameters:
    ///   - userActivityPubId: User's ActivityPub id who blocked the domain.
    ///   - actorId: The ActivityPub actor ID (URL) to check.
    ///   - context: The execution context providing services and database access.
    /// - Returns: Returns `true` if the domain is blocked by the user, otherwise `false`.
    /// - Throws: Throws an error if the check fails.
    func isDomainBlockedByUser(userActivityPubId: String, actorId: String, on context: ExecutionContext) async throws -> Bool

    /// Checks if the domain of the actor ID is blocked by the user.
    ///
    /// - Parameters:
    ///   - userId: User who blocked the domain.
    ///   - actorId: The ActivityPub actor ID (URL) to check.
    ///   - context: The execution context providing services and database access.
    /// - Returns: Returns `true` if the domain is blocked by the user, otherwise `false`.
    /// - Throws: Throws an error if the check fails.
    func isDomainBlockedByUser(userId: Int64, actorId: String, on context: ExecutionContext) async throws -> Bool
}

/// A service for managing domains blocked by the user.
final class UserBlockedDomainsService: UserBlockedDomainsServiceType {
    public func exists(userId: Int64, url: URL, on database: Database) async throws -> Bool {
        guard let host = url.host else {
            return false
        }

        let normalizedHost = host.lowercased()
        let count = try await UserBlockedDomain.query(on: database)
            .filter(\.$user.$id == userId)
            .filter(\.$domain == normalizedHost)
            .count()

        return count > 0
    }

    public func isDomainBlockedByUser(userActivityPubId: String, actorId: String, on context: ExecutionContext) async throws -> Bool {
        let usersService = context.services.usersService

        guard let url = URL(string: actorId) else {
            return false
        }

        guard let user = try await usersService.get(activityPubProfile: userActivityPubId, on: context.db) else {
            return true
        }

        return try await self.exists(userId: user.requireID(), url: url, on: context.db)
    }

    public func isDomainBlockedByUser(userId: Int64, actorId: String, on context: ExecutionContext) async throws -> Bool {
        guard let url = URL(string: actorId) else {
            return false
        }

        return try await self.exists(userId: userId, url: url, on: context.db)
    }
}

