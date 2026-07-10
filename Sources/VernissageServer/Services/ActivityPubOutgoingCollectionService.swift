//
//  https://mczachurski.dev
//  Copyright © 2026 Marcin Czachurski and the repository contributors.
//  Licensed under the Apache License 2.0.
//

import Vapor
import ActivityPubKit

extension Application.Services {
    struct ActivityPubOutgoingCollectionServiceKey: StorageKey {
        typealias Value = ActivityPubOutgoingCollectionServiceType
    }

    var activityPubOutgoingCollectionService: ActivityPubOutgoingCollectionServiceType {
        get {
            self.application.storage[ActivityPubOutgoingCollectionServiceKey.self] ?? ActivityPubOutgoingCollectionService()
        }
        nonmutating set {
            self.application.storage[ActivityPubOutgoingCollectionServiceKey.self] = newValue
        }
    }
}

@_documentation(visibility: private)
protocol ActivityPubOutgoingCollectionServiceType: Sendable {
    /// Sends an ActivityPub featured collection change for a local status.
    ///
    /// The method loads the status from the local database, skips non-local statuses, and signs outgoing `Add`
    /// or `Remove` activities with the status owner's private key. The activity is delivered to shared inboxes
    /// of the user's followers so remote instances can update their cached featured collection state.
    /// Invalid inbox URLs and delivery errors for individual inboxes are logged and do not stop delivery to
    /// the remaining inboxes.
    ///
    /// - Parameters:
    ///   - statusId: The local identifier of the status added to or removed from the featured collection.
    ///   - type: The ActivityPub activity type to send. Only `Add` and `Remove` produce outgoing requests.
    ///   - context: The execution context providing services and database access.
    /// - Throws: Database errors when loading the status or followers' shared inboxes fails.
    func sendFeaturedChange(for statusId: Int64, type: ActivityTypeDto, on context: ExecutionContext) async throws
}

final class ActivityPubOutgoingCollectionService: ActivityPubOutgoingCollectionServiceType {
    public func sendFeaturedChange(for statusId: Int64, type: ActivityTypeDto, on context: ExecutionContext) async throws {
        let statusesService = context.services.statusesService
        let followsService = context.services.followsService
        let snowflakeService = context.services.snowflakeService

        guard let status = try await statusesService.get(id: statusId, on: context.db) else {
            context.logger.warning("Cannot send '\(type.rawValue)' for featured collection. Status not found (id: \(statusId)).")
            return
        }

        guard status.user.isLocal else {
            context.logger.info("Skipping '\(type.rawValue)' for non-local status: '\(status.stringId() ?? "")'.")
            return
        }

        guard let privateKey = status.user.privateKey else {
            context.logger.warning("Cannot send '\(type.rawValue)' for featured collection. Missing private key for user '\(status.user.userName)'.")
            return
        }

        let followersInboxes = try await followsService.getFollowersOfSharedInboxes(followersOf: status.$user.id, on: context)
        let targetCollection = status.user.featured ?? "\(status.user.activityPubProfile)/featured"

        for inbox in followersInboxes {
            guard let inboxUrl = URL(string: inbox) else {
                context.logger.warning("Skipping '\(type.rawValue)' for featured collection. Invalid inbox URL '\(inbox)'.")
                continue
            }

            let activityPubClient = ActivityPubClient(privatePemKey: privateKey,
                                                      userAgent: Constants.userAgent,
                                                      host: inboxUrl.host)
            let requestId = snowflakeService.generate()

            do {
                switch type {
                case .add:
                    try await activityPubClient.addToFeatured(objectId: status.activityPubId,
                                                              actorId: status.user.activityPubProfile,
                                                              targetId: targetCollection,
                                                              on: inboxUrl,
                                                              withId: requestId)
                case .remove:
                    try await activityPubClient.removeFromFeatured(objectId: status.activityPubId,
                                                                   actorId: status.user.activityPubProfile,
                                                                   targetId: targetCollection,
                                                                   on: inboxUrl,
                                                                   withId: requestId)
                default:
                    break
                }
            } catch {
                context.logger.warning("Sending '\(type.rawValue)' to inbox failed (inbox: \(inboxUrl.absoluteString), status: \(status.activityPubId)). Error: \(error).")
            }
        }
    }
}
