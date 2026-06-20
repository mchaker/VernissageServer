//
//  https://mczachurski.dev
//  Copyright © 2024 Marcin Czachurski and the repository contributors.
//  Licensed under the Apache License 2.0.
//

import Vapor
import Fluent
import ActivityPubKit

extension Application.Services {
    struct InstanceBlockedDomainsServiceKey: StorageKey {
        typealias Value = InstanceBlockedDomainsServiceType
    }

    var instanceBlockedDomainsService: InstanceBlockedDomainsServiceType {
        get {
            self.application.storage[InstanceBlockedDomainsServiceKey.self] ?? InstanceBlockedDomainsService()
        }
        nonmutating set {
            self.application.storage[InstanceBlockedDomainsServiceKey.self] = newValue
        }
    }
}

@_documentation(visibility: private)
protocol InstanceBlockedDomainsServiceType: Sendable {
    /// Checks if a given domain (from the provided URL) is blocked by the instance.
    ///
    /// - Parameters:
    ///   - url: The URL whose domain will be checked against the instance's block list.
    ///   - database: The database connection to use.
    /// - Returns: True if the domain is blocked, false otherwise.
    /// - Throws: An error if the database query fails.
    func exists(url: URL, on database: Database) async throws -> Bool

    /// Checks if the domain of the actor ID is blocked by the local instance.
    ///
    /// - Parameters:
    ///   - activityPubId: The ActivityPub actor/object ID (URL) to check.
    ///   - context: The execution context providing services and database access.
    /// - Returns: Returns `true` if the domain is blocked, otherwise `false`.
    /// - Throws: Throws an error if the check fails.
    func isDomainBlockedByInstance(activityPubId: String, on context: ExecutionContext) async throws -> Bool

    /// Checks if the domain of the actor in the given activity is blocked by the local instance.
    ///
    /// - Parameters:
    ///   - activity: The ActivityPub activity DTO to check.
    ///   - context: The execution context providing services and database access.
    /// - Returns: Returns `true` if the domain is blocked, otherwise `false`.
    /// - Throws: Throws an error if the check fails.
    func isDomainBlockedByInstance(activity: ActivityDto, on context: ExecutionContext) async throws -> Bool
}

/// A service for managing domains blocked by the instance.
final class InstanceBlockedDomainsService: InstanceBlockedDomainsServiceType {
    public func exists(url: URL, on database: Database) async throws -> Bool {
        guard let host = url.host else {
            return false
        }

        let normalizedHost = host.lowercased()
        let count = try await InstanceBlockedDomain.query(on: database)
            .filter(\.$domain == normalizedHost)
            .count()

        return count > 0
    }

    public func isDomainBlockedByInstance(activityPubId: String, on context: ExecutionContext) async throws -> Bool {
        let instanceBlockedDomainsService = context.services.instanceBlockedDomainsService

        guard let url = URL(string: activityPubId) else {
            return false
        }

        return try await instanceBlockedDomainsService.exists(url: url, on: context.db)
    }

    public func isDomainBlockedByInstance(activity: ActivityDto, on context: ExecutionContext) async throws -> Bool {
        let instanceBlockedDomainsService = context.services.instanceBlockedDomainsService

        guard let activityPubProfile = activity.actor.actorIds().first else {
            return false
        }

        guard let url = URL(string: activityPubProfile) else {
            return false
        }

        return try await instanceBlockedDomainsService.exists(url: url, on: context.db)
    }
}
