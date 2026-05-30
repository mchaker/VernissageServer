//
//  https://mczachurski.dev
//  Copyright © 2024 Marcin Czachurski and the repository contributors.
//  Licensed under the Apache License 2.0.
//

import Vapor
import FluentKit
import ActivityPubKit

extension Application.Services {
    struct ActivityPubOutgoingUserServiceKey: StorageKey {
        typealias Value = ActivityPubOutgoingUserServiceType
    }

    var activityPubOutgoingUserService: ActivityPubOutgoingUserServiceType {
        get {
            self.application.storage[ActivityPubOutgoingUserServiceKey.self] ?? ActivityPubOutgoingUserService()
        }
        nonmutating set {
            self.application.storage[ActivityPubOutgoingUserServiceKey.self] = newValue
        }
    }
}

@_documentation(visibility: private)
protocol ActivityPubOutgoingUserServiceType: Sendable {
    /// Sends profile update as ActivityPub Update(Person) to remote mutual relationships of a local user.
    ///
    /// - Parameters:
    ///   - userId: The Id of the local user whose profile update should be sent.
    ///   - context: The execution context containing services and database access.
    /// - Throws: An error if preparing or sending updates fails.
    func update(userId: Int64, on context: ExecutionContext) async throws
    
    /// Sends a request to delete a local user to all remote servers (shared inbox), notifying them about the account removal.
    /// - Parameters:
    ///   - userId: The identifier of the user to be deleted (local users only).
    ///   - context: Queue context for async operations.
    /// - Throws: Errors related to retrieving the user, missing private key, or network errors when sending the request.
    func delete(userId: Int64, on context: ExecutionContext) async throws
}

final class ActivityPubOutgoingUserService: ActivityPubOutgoingUserServiceType {
    func update(userId: Int64, on context: ExecutionContext) async throws {
        let usersService = context.services.usersService
        let followsService = context.services.followsService
        let snowflakeService = context.services.snowflakeService
        let suspendedServersService = context.services.suspendedServersService

        guard let updatedUser = try await usersService.get(id: userId, on: context.db) else {
            context.logger.warning("Profile update cannot be sent. User '\(userId)' not found.")
            return
        }

        guard updatedUser.isLocal else {
            context.logger.warning("Profile update cannot be sent. User '\(userId)' is remote.")
            return
        }

        guard let privateKey = updatedUser.privateKey else {
            context.logger.warning("Profile update cannot be sent. Missing private key for user '\(userId)'.")
            return
        }

        let followersInboxes = try await followsService.getFollowersOfSharedInboxes(followersOf: userId, on: context)
        let followingInboxes = try await followsService.getFollowingOfSharedInboxes(followingBy: userId, on: context)
        let inboxes = Array(Set(followersInboxes).intersection(Set(followingInboxes)))

        guard inboxes.isEmpty == false else {
            context.logger.info("Profile update skipped. No mutual remote users for '\(updatedUser.userName)'.")
            return
        }

        let personDto = try await usersService.getPersonDto(for: updatedUser, on: context)
        let updateId = snowflakeService.generate()
        let published = updatedUser.updatedAt ?? Date()

        let inboxUrls = inboxes.compactMap { URL(string: $0) }

        // Download suspended servers list.
        let suspendedServers = await suspendedServersService.getSnapshot(on: context)

        for (index, inboxUrl) in inboxUrls.enumerated() {
            let shouldSend = await suspendedServersService.shouldSend(to: inboxUrl.host, basedOn: suspendedServers)
            guard shouldSend else {
                context.logger.warning("Sending profile update skipped for suspended host: '\(inboxUrl.host ?? "<unknown>")'.")
                continue
            }

            context.logger.info("[\(index + 1)/\(inboxUrls.count)] Sending profile update for '\(updatedUser.userName)' to inbox: '\(inboxUrl.absoluteString)'.")
            let activityPubClient = ActivityPubClient(privatePemKey: privateKey, userAgent: Constants.userAgent, host: inboxUrl.host)

            do {
                try await activityPubClient.update(person: personDto,
                                                   activityPubProfile: updatedUser.activityPubProfile,
                                                   on: inboxUrl,
                                                   withId: updateId,
                                                   published: published)
                try? await suspendedServersService.registerSuccess(for: inboxUrl.host, on: context)
            } catch {
                try? await suspendedServersService.registerConnectionError(for: inboxUrl.host, error: error, on: context)
                await context.logger.store("Sending profile update to inbox error.", error, on: context.application)
            }
        }
    }
    
    func delete(userId: Int64, on context: ExecutionContext) async throws {
        guard let userToDelete = try await User.query(on: context.application.db)
            .withDeleted()
            .filter(\.$id == userId)
            .first() else {
            context.logger.warning("User: '\(userId)' cannot exists in database.")
            return
        }

        guard userToDelete.isLocal else {
            context.logger.warning("User: '\(userId)' doesn't have to be deleted from remote server (it's remote user).")
            return
        }

        guard let privateKey = userToDelete.privateKey else {
            context.logger.warning("User: '\(userId)' cannot be send to shared inbox (delete). Missing private key.")
            return
        }

        let users = try await User.query(on: context.application.db)
            .filter(\.$isLocal == false)
            .field(\.$sharedInbox)
            .unique()
            .all()

        let sharedInboxes = users.map({  $0.sharedInbox })
        for (index, sharedInbox) in sharedInboxes.enumerated() {
            guard let sharedInbox, let sharedInboxUrl = URL(string: sharedInbox) else {
                context.logger.warning("User delete: '\(userToDelete.userName)' cannot be send to shared inbox url: '\(sharedInbox ?? "")'.")
                continue
            }

            context.logger.info("[\(index + 1)/\(sharedInboxes.count)] Sending user delete: '\(userToDelete.userName)' to shared inbox: '\(sharedInboxUrl.absoluteString)'.")
            let activityPubClient = ActivityPubClient(privatePemKey: privateKey, userAgent: Constants.userAgent, host: sharedInboxUrl.host)

            do {
                try await activityPubClient.delete(actorId: userToDelete.activityPubProfile, on: sharedInboxUrl)
            } catch {
                if error is NetworkError || error.isConnectionError {
                    context.logger.warning("Sending user delete to shared inbox error. Shared inbox url: \(sharedInboxUrl). Error: \(error).")
                } else {
                    await context.logger.store("Sending user delete to shared inbox error.", error, on: context.application)
                }
            }
        }
    }
}
