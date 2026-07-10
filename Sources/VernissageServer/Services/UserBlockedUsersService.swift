//
//  https://mczachurski.dev
//  Copyright © 2026 Marcin Czachurski and the repository contributors.
//  Licensed under the Apache License 2.0.
//

import Vapor
import Fluent
import ActivityPubKit

extension Application.Services {
    struct UserBlockedUsersServiceKey: StorageKey {
        typealias Value = UserBlockedUsersServiceType
    }

    var userBlockedUsersService: UserBlockedUsersServiceType {
        get {
            self.application.storage[UserBlockedUsersServiceKey.self] ?? UserBlockedUsersService()
        }
        nonmutating set {
            self.application.storage[UserBlockedUsersServiceKey.self] = newValue
        }
    }
}

@_documentation(visibility: private)
protocol UserBlockedUsersServiceType: Sendable {
    /// Checks whether the given domain (host from URL) is blocked by the user.
    /// - Parameters:
    ///   - userId: Signed in user.
    ///   - blockedUserId:Blocked user.
    ///   - database: Database to perform the query on.
    /// - Returns: True if the user is blocked by the signed in user.
    /// - Throws: Database errors.
    func exists(userId: Int64, blockedUserId: Int64, on database: Database) async throws -> Bool

    /// Returns list od blocked user Id's.
    /// - Parameters:
    ///   - userId: Signed in user.
    ///   - database: Database to perform the query on.
    /// - Returns: List of user ids which are blocked by signed in user.
    /// - Throws: Database errors.
    func blockedUsers(forUserId userId: Int64, on database: Database) async throws -> [Int64]

    /// Checks if the user of the actor ID is blocked by the user.
    ///
    /// - Parameters:
    ///   - userActivityPubId: User's ActivityPub id who blocked the domain.
    ///   - actorId: The ActivityPub actor ID (URL) to check.
    ///   - context: The execution context providing services and database access.
    /// - Returns: Returns `true` if the user is blocked by the user, otherwise `false`.
    /// - Throws: Throws an error if the check fails.
    func isUserBlockedByUser(userActivityPubId: String, actorId: String, on context: ExecutionContext) async throws -> Bool
}

/// A service for managing domains blocked by the user.
final class UserBlockedUsersService: UserBlockedUsersServiceType {
    public func exists(userId: Int64, blockedUserId: Int64, on database: Database) async throws -> Bool {
        let count = try await UserBlockedUser.query(on: database)
            .filter(\.$user.$id == userId)
            .filter(\.$blockedUser.$id == blockedUserId)
            .count()

        return count > 0
    }

    public func blockedUsers(forUserId userId: Int64, on database: Database) async throws -> [Int64] {
        let userBlocedUsers = try await UserBlockedUser.query(on: database)
            .filter(\.$user.$id == userId)
            .field(\.$blockedUser.$id)
            .all()

        return userBlocedUsers.map({ $0.$blockedUser.id })
    }

    public func isUserBlockedByUser(userActivityPubId: String, actorId: String, on context: ExecutionContext) async throws -> Bool {
        let userBlockedUsersService = context.services.userBlockedUsersService
        let usersService = context.services.usersService

        guard let user = try await usersService.get(activityPubProfile: userActivityPubId, on: context.db) else {
            return true
        }

        guard let blockedUser = try await usersService.get(activityPubProfile: actorId, on: context.db) else {
            return true
        }

        return try await userBlockedUsersService.exists(userId: user.requireID(), blockedUserId: blockedUser.requireID(), on: context.db)
    }
}

