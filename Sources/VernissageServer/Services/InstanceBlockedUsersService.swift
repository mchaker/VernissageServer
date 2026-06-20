//
//  https://mczachurski.dev
//  Copyright © 2026 Marcin Czachurski and the repository contributors.
//  Licensed under the Apache License 2.0.
//

import Vapor
import Fluent
import ActivityPubKit

extension Application.Services {
    struct InstanceBlockedUsersServiceKey: StorageKey {
        typealias Value = InstanceBlockedUsersServiceType
    }

    var instanceBlockedUsersService: InstanceBlockedUsersServiceType {
        get {
            self.application.storage[InstanceBlockedUsersServiceKey.self] ?? InstanceBlockedUsersService()
        }
        nonmutating set {
            self.application.storage[InstanceBlockedUsersServiceKey.self] = newValue
        }
    }
}

@_documentation(visibility: private)
protocol InstanceBlockedUsersServiceType: Sendable {
    /// Checks if the actor ID is blocked by the local instance.
    ///
    /// - Parameters:
    ///   - activityPubId: The ActivityPub actor/object ID (URL) to check.
    ///   - context: The execution context providing services and database access.
    /// - Returns: Returns `true` if the actor is blocked, otherwise `false`.
    /// - Throws: Throws an error if the check fails.
    func isActorBlockedByInstance(activityPubId: String, on context: ExecutionContext) async throws -> Bool

    /// Checks if the actor in the given activity is blocked by the local instance.
    ///
    /// - Parameters:
    ///   - activity: The ActivityPub activity DTO to check.
    ///   - context: The execution context providing services and database access.
    /// - Returns: Returns `true` if the actor is blocked, otherwise `false`.
    /// - Throws: Throws an error if the check fails.
    func isActorBlockedByInstance(activity: ActivityDto, on context: ExecutionContext) async throws -> Bool
}

/// A service for managing domains blocked by the instance.
final class InstanceBlockedUsersService: InstanceBlockedUsersServiceType {
    public func isActorBlockedByInstance(activityPubId: String, on context: ExecutionContext) async throws -> Bool {
        let activityPubProfileNormalized = activityPubId.uppercased()
        let exists = try await User.query(on: context.db)
            .filter(\.$activityPubProfileNormalized == activityPubProfileNormalized)
            .filter(\.$isBlocked == true)
            .filter(\.$isLocal == false)
            .count()

        return exists > 0
    }

    public func isActorBlockedByInstance(activity: ActivityDto, on context: ExecutionContext) async throws -> Bool {
        guard let activityPubProfile = activity.actor.actorIds().first else {
            return false
        }

        return try await self.isActorBlockedByInstance(activityPubId: activityPubProfile, on: context)
    }
}
