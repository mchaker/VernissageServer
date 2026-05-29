//
//  https://mczachurski.dev
//  Copyright © 2024 Marcin Czachurski and the repository contributors.
//  Licensed under the Apache License 2.0.
//

import Vapor
import Fluent
import Queues
import ActivityPubKit

extension Application.Services {
    struct ActivityPubOutgoingStatusServiceKey: StorageKey {
        typealias Value = ActivityPubOutgoingStatusServiceType
    }

    var activityPubOutgoingStatusService: ActivityPubOutgoingStatusServiceType {
        get {
            self.application.storage[ActivityPubOutgoingStatusServiceKey.self] ?? ActivityPubOutgoingStatusService()
        }
        nonmutating set {
            self.application.storage[ActivityPubOutgoingStatusServiceKey.self] = newValue
        }
    }
}

@_documentation(visibility: private)
protocol ActivityPubOutgoingStatusServiceType: Sendable {
    /// Creates and distributes a status based on the given ActivityPub status event.
    ///
    /// Processes the status creation and sends it to remote shared inboxes, handling network communication and activity event lifecycle.
    ///
    /// - Parameters:
    ///   - statusActivityPubEvent: The event describing the status creation and its distribution targets.
    ///   - context: The execution context providing services and database access.
    /// - Throws: Throws an error if the status could not be sent, or if validation or processing fails.
    func create(statusActivityPubEvent: StatusActivityPubEvent, on context: ExecutionContext) async throws

    /// Updates status information based on an ActivityPub status event.
    ///
    /// Processes and sends updates for a status to remote shared inboxes, handling network communication and status history.
    ///
    /// - Parameters:
    ///   - statusActivityPubEvent: The event describing the status update and its distribution targets.
    ///   - context: The execution context providing services and database access.
    /// - Throws: Throws an error if the update could not be sent, history cannot be retrieved, or validation fails during processing.
    func update(statusActivityPubEvent: StatusActivityPubEvent, on context: ExecutionContext) async throws

    /// Creates and distributes a like (favourite) activity based on the given status event.
    ///
    /// Processes the creation and remote distribution of a like/favourite for a status, handling network communication and event lifecycle.
    ///
    /// - Parameters:
    ///   - statusActivityPubEvent: The event describing the like action and its distribution targets.
    ///   - statusFavouriteId: The identifier of the status favourite (like) to be sent.
    ///   - context: The execution context providing services and database access.
    /// - Throws: Throws an error if the like cannot be sent, or if validation or processing fails.
    func like(statusActivityPubEvent: StatusActivityPubEvent, statusFavouriteId: String?, on context: ExecutionContext) async throws

    /// Creates and distributes an unlike (unfavourite) activity based on the given status event.
    ///
    /// Processes the removal and remote distribution of a like/favourite for a status, handling network communication and event lifecycle.
    ///
    /// - Parameters:
    ///   - statusActivityPubEvent: The event describing the unlike action and its distribution targets.
    ///   - statusFavouriteId: The identifier of the status favourite (like) to be removed.
    ///   - context: The execution context providing services and database access.
    /// - Throws: Throws an error if the unlike cannot be sent, or if validation or processing fails.
    func unlike(statusActivityPubEvent: StatusActivityPubEvent, statusFavouriteId: String?, on context: ExecutionContext) async throws

    /// Creates and distributes an announce (boost/reblog) activity based on the given status event.
    ///
    /// Processes the creation and remote distribution of an announce/boost for a status, handling network communication and event lifecycle.
    ///
    /// - Parameters:
    ///   - statusActivityPubEvent: The event describing the announce action and its distribution targets.
    ///   - activityPubReblog: The data describing the reblog/boost, or `nil` if not available.
    ///   - context: The execution context providing services and database access.
    /// - Throws: Throws an error if the announce cannot be sent, or if validation or processing fails.
    func announce(statusActivityPubEvent: StatusActivityPubEvent, activityPubReblog: ActivityPubReblogDto?, on context: ExecutionContext) async throws

    /// Creates and distributes an unannounce (undo boost/unreblog) activity based on the given status event.
    ///
    /// Processes the removal and remote distribution of a previous announce/boost for a status, handling network communication and event lifecycle.
    ///
    /// - Parameters:
    ///   - statusActivityPubEvent: The event describing the unannounce action and its distribution targets.
    ///   - activityPubUnreblog: The data describing the unboost/unreblog, or `nil` if not available.
    ///   - context: The execution context providing services and database access.
    /// - Throws: Throws an error if the unannounce cannot be sent, or if validation or processing fails.
    func unannounce(statusActivityPubEvent: StatusActivityPubEvent, activityPubUnreblog: ActivityPubUnreblogDto?, on context: ExecutionContext) async throws

    /// Creates and distributes a pin activity (`Add` to featured collection) based on the given status event.
    ///
    /// - Parameters:
    ///   - statusActivityPubEvent: The event describing the pin action and its distribution targets.
    ///   - context: The execution context providing services and database access.
    /// - Throws: Throws an error if the pin cannot be sent, or if validation or processing fails.
    func pin(statusActivityPubEvent: StatusActivityPubEvent, on context: ExecutionContext) async throws

    /// Creates and distributes an unpin activity (`Remove` from featured collection) based on the given status event.
    ///
    /// - Parameters:
    ///   - statusActivityPubEvent: The event describing the unpin action and its distribution targets.
    ///   - context: The execution context providing services and database access.
    /// - Throws: Throws an error if the unpin cannot be sent, or if validation or processing fails.
    func unpin(statusActivityPubEvent: StatusActivityPubEvent, on context: ExecutionContext) async throws
}

/// Service responsible for sending requests to Activity Pub remote instances.
final class ActivityPubOutgoingStatusService: ActivityPubOutgoingStatusServiceType {

    public func create(statusActivityPubEvent: StatusActivityPubEvent, on context: ExecutionContext) async throws {
        try await statusActivityPubEvent.start(on: context)

        let statusesService = context.services.statusesService
        let suspendedServersService = context.services.suspendedServersService

        guard let status = try await self.getStatus(statusActivityPubEvent: statusActivityPubEvent, on: context) else {
            return
        }

        // Private key is required for sending ActivityPub request.
        guard let privateKey = try await self.getPrivateKey(statusActivityPubEvent: statusActivityPubEvent, on: context) else {
            return
        }

        // Get information about reply status.
        let replyToStatus: Status? = if let replyToStatusId = status.$replyToStatus.id {
            try await statusesService.get(id: replyToStatusId, on: context.application.db)
        } else {
            nil
        }

        // Download suspended servers list.
        let suspendedServers = await suspendedServersService.getSnapshot(on: context)

        // Prepare note DTO object.
        let noteDto = try await statusesService.note(basedOn: status, replyToStatus: replyToStatus, on: context)

        // Try to send update only to hosts which we didn't sent update yet.
        let eventItemsToProceed = statusActivityPubEvent.statusActivityPubEventItems.filter { $0.isSuccess == nil }

        // Send created note to all inboxes.
        for (index, eventItem) in eventItemsToProceed.enumerated() {
            try await eventItem.start(on: context)

            // Translate string into URL.
            guard let sharedInboxUrl = URL(string: eventItem.url) else {
                let errorMessage = "Status: '\(status.stringId() ?? "")' cannot be send to shared inbox url: '\(eventItem.url)'. Incorrect url."

                try? await eventItem.error(errorMessage, on: context)
                context.logger.warning("\(errorMessage)")
                continue
            }

            let shouldSend = await suspendedServersService.shouldSend(to: sharedInboxUrl.host, basedOn: suspendedServers)
            guard shouldSend else {
                try? await eventItem.suspended(on: context)
                context.logger.warning("Sending create status skipped for suspended host: '\(sharedInboxUrl.host ?? "<unknown>")'.")
                continue
            }

            // Prepare ActivityPub client.
            context.logger.info("[\(index + 1)/\(eventItemsToProceed.count)] Sending create status: '\(status.stringId() ?? "")' to shared inbox: '\(sharedInboxUrl.absoluteString)'.")
            let activityPubClient = ActivityPubClient(privatePemKey: privateKey, userAgent: Constants.userAgent, host: sharedInboxUrl.host)

            do {
                // Send status create via network to remote server.
                try await activityPubClient.create(note: noteDto,
                                                   activityPubProfile: noteDto.attributedTo,
                                                   activityPubReplyProfile: replyToStatus?.user.activityPubProfile,
                                                   on: sharedInboxUrl)

                // Mark event item as finished successfully.
                try? await eventItem.success(on: context)
                try? await suspendedServersService.registerSuccess(for: sharedInboxUrl.host, on: context)
            } catch {
                // Mark event item as finished with error.
                try? await eventItem.error("\(error)", on: context)
                try? await suspendedServersService.registerConnectionError(for: sharedInboxUrl.host, error: error, on: context)
                context.logger.warning("Sending create status to shared inbox error. Shared inbox url: \(sharedInboxUrl). Error: \(error).")
            }
        }

        // Mark event as finished successfully.
        let hasFailedEvents = statusActivityPubEvent.statusActivityPubEventItems.contains(where: { $0.isSuccess == false || $0.isSuspended == true })
        try await statusActivityPubEvent.success(result: hasFailedEvents ? .finishedWithErrors : .finished, on: context)
    }

    public func update(statusActivityPubEvent: StatusActivityPubEvent, on context: ExecutionContext) async throws {
        try await statusActivityPubEvent.start(on: context)

        let statusesService = context.services.statusesService
        let suspendedServersService = context.services.suspendedServersService

        guard let status = try await self.getStatus(statusActivityPubEvent: statusActivityPubEvent, on: context) else {
            return
        }

        // Private key is required for sending ActivityPub request.
        guard let privateKey = try await self.getPrivateKey(statusActivityPubEvent: statusActivityPubEvent, on: context) else {
            return
        }

        // Status history item is required for sending ActivityPub update status request.
        guard let statusHistory = try await self.getStatusHistory(statusActivityPubEvent: statusActivityPubEvent, on: context) else {
            return
        }

        // Get information about reply status.
        let replyToStatus: Status? = if let replyToStatusId = status.$replyToStatus.id {
            try await statusesService.get(id: replyToStatusId, on: context.application.db)
        } else {
            nil
        }

        // Download suspended servers list.
        let suspendedServers = await suspendedServersService.getSnapshot(on: context)

        // Prepare note DTO object.
        let noteDto = try await statusesService.note(basedOn: status, replyToStatus: replyToStatus, on: context)

        // Try to send update only to hosts which we didn't sent update yet.
        let eventItemsToProceed = statusActivityPubEvent.statusActivityPubEventItems.filter { $0.isSuccess == nil }

        // Send updated note to all inboxes.
        for (index, eventItem) in eventItemsToProceed.enumerated() {
            try await eventItem.start(on: context)

            // Translate string into URL.
            guard let sharedInboxUrl = URL(string: eventItem.url) else {
                let errorMessage = "Status update: '\(status.stringId() ?? "")' cannot be send to shared inbox url: '\(eventItem.url)'. Incorrect url."

                try? await eventItem.error(errorMessage, on: context)
                context.logger.warning("\(errorMessage)")
                continue
            }

            let shouldSend = await suspendedServersService.shouldSend(to: sharedInboxUrl.host, basedOn: suspendedServers)
            guard shouldSend else {
                try? await eventItem.suspended(on: context)
                context.logger.warning("Sending update status skipped for suspended host: '\(sharedInboxUrl.host ?? "<unknown>")'.")
                continue
            }

            // Prepare ActivityPub client.
            context.logger.info("[\(index + 1)/\(eventItemsToProceed.count)] Sending update status: '\(status.stringId() ?? "")' to shared inbox: '\(sharedInboxUrl.absoluteString)'.")
            let activityPubClient = ActivityPubClient(privatePemKey: privateKey, userAgent: Constants.userAgent, host: sharedInboxUrl.host)

            do {
                // Send status update via network to remote server.
                try await activityPubClient.update(historyId: statusHistory.stringId() ?? "",
                                                   published: status.updatedAt ?? Date(),
                                                   note: noteDto,
                                                   activityPubProfile: noteDto.attributedTo,
                                                   activityPubReplyProfile: replyToStatus?.user.activityPubProfile,
                                                   on: sharedInboxUrl)

                // Mark event item as finished successfully.
                try? await eventItem.success(on: context)
                try? await suspendedServersService.registerSuccess(for: sharedInboxUrl.host, on: context)
            } catch {
                // Mark event item as finished with error.
                try? await eventItem.error("\(error)", on: context)
                try? await suspendedServersService.registerConnectionError(for: sharedInboxUrl.host, error: error, on: context)
                context.logger.warning("Sending update status to shared inbox error. Shared inbox url: \(sharedInboxUrl). Error: \(error).")
            }
        }

        // Mark event as finished successfully.
        let hasFailedEvents = statusActivityPubEvent.statusActivityPubEventItems.contains(where: { $0.isSuccess == false || $0.isSuspended == true })
        try await statusActivityPubEvent.success(result: hasFailedEvents ? .finishedWithErrors : .finished, on: context)
    }

    public func like(statusActivityPubEvent: StatusActivityPubEvent, statusFavouriteId: String?, on context: ExecutionContext) async throws {
        try await statusActivityPubEvent.start(on: context)

        // Private key is required for sending ActivityPub request.
        guard let privateKey = try await self.getPrivateKey(statusActivityPubEvent: statusActivityPubEvent, on: context) else {
            return
        }

        let usersService = context.services.usersService
        let suspendedServersService = context.services.suspendedServersService

        guard let status = try await self.getStatus(statusActivityPubEvent: statusActivityPubEvent, on: context) else {
            return
        }

        guard let user = try await usersService.get(id: statusActivityPubEvent.user.requireID(), on: context.db) else {
            return
        }

        guard let statusFavouriteId else {
            let errorMessage = "Status favourite: '\(status.stringId() ?? "")' cannot be send to shared inbox. Missing status favourite id."

            // Mark event as finished with error.
            try await statusActivityPubEvent.error(errorMessage, on: context)

            context.logger.warning("\(errorMessage)")
            return
        }

        // Download suspended servers list.
        let suspendedServers = await suspendedServersService.getSnapshot(on: context)

        // Try to send update only to hosts which we didn't sent update yet.
        let eventItemsToProceed = statusActivityPubEvent.statusActivityPubEventItems.filter { $0.isSuccess == nil }

        // Send updated note to all inboxes.
        for (index, eventItem) in eventItemsToProceed.enumerated() {
            try await eventItem.start(on: context)

            // Translate string into URL.
            guard let sharedInboxUrl = URL(string: eventItem.url) else {
                let errorMessage = "Favourite: '\(status.stringId() ?? "")' cannot be send to shared inbox url: '\(eventItem.url)'. Incorrect url."

                try? await eventItem.error(errorMessage, on: context)
                context.logger.warning("\(errorMessage)")
                continue
            }

            let shouldSend = await suspendedServersService.shouldSend(to: sharedInboxUrl.host, basedOn: suspendedServers)
            guard shouldSend else {
                try? await eventItem.suspended(on: context)
                context.logger.warning("Sending favourite skipped for suspended host: '\(sharedInboxUrl.host ?? "<unknown>")'.")
                continue
            }

            // Prepare ActivityPub client.
            context.logger.info("[\(index + 1)/\(eventItemsToProceed.count)] Sending favourite: '\(statusFavouriteId)' to shared inbox: '\(sharedInboxUrl.absoluteString)'.")
            let activityPubClient = ActivityPubClient(privatePemKey: privateKey, userAgent: Constants.userAgent, host: sharedInboxUrl.host)

            do {
                // Send status favourite via network to remote server.
                try await activityPubClient.like(statusFavouriteId: statusFavouriteId,
                                                 activityPubStatusId: status.activityPubId,
                                                 activityPubProfile: user.activityPubProfile,
                                                 on: sharedInboxUrl)

                // Mark event item as finished successfully.
                try? await eventItem.success(on: context)
                try? await suspendedServersService.registerSuccess(for: sharedInboxUrl.host, on: context)
            } catch {
                // Mark event item as finished with error.
                try? await eventItem.error("\(error)", on: context)
                try? await suspendedServersService.registerConnectionError(for: sharedInboxUrl.host, error: error, on: context)
                context.logger.warning("Sending favourite to shared inbox error. Shared inbox url: \(sharedInboxUrl). Error: \(error).")
            }
        }

        // Mark event as finished successfully.
        let hasFailedEvents = statusActivityPubEvent.statusActivityPubEventItems.contains(where: { $0.isSuccess == false || $0.isSuspended == true })
        try await statusActivityPubEvent.success(result: hasFailedEvents ? .finishedWithErrors : .finished, on: context)
    }

    public func unlike(statusActivityPubEvent: StatusActivityPubEvent, statusFavouriteId: String?, on context: ExecutionContext) async throws {
        try await statusActivityPubEvent.start(on: context)

        // Private key is required for sending ActivityPub request.
        guard let privateKey = try await self.getPrivateKey(statusActivityPubEvent: statusActivityPubEvent, on: context) else {
            return
        }

        let usersService = context.services.usersService
        let suspendedServersService = context.services.suspendedServersService

        guard let status = try await self.getStatus(statusActivityPubEvent: statusActivityPubEvent, on: context) else {
            return
        }

        guard let user = try await usersService.get(id: statusActivityPubEvent.user.requireID(), on: context.db) else {
            return
        }

        guard let statusFavouriteId else {
            let errorMessage = "Status unfavourite: '\(status.stringId() ?? "")' cannot be send to shared inbox. Missing status favourite id."

            // Mark event as finished with error.
            try await statusActivityPubEvent.error(errorMessage, on: context)

            context.logger.warning("\(errorMessage)")
            return
        }

        // Download suspended servers list.
        let suspendedServers = await suspendedServersService.getSnapshot(on: context)

        // Try to send update only to hosts which we didn't sent update yet.
        let eventItemsToProceed = statusActivityPubEvent.statusActivityPubEventItems.filter { $0.isSuccess == nil }

        // Send updated note to all inboxes.
        for (index, eventItem) in eventItemsToProceed.enumerated() {
            try await eventItem.start(on: context)

            // Translate string into URL.
            guard let sharedInboxUrl = URL(string: eventItem.url) else {
                let errorMessage = "Unfavourite: '\(status.stringId() ?? "")' cannot be send to shared inbox url: '\(eventItem.url)'. Incorrect url."

                try? await eventItem.error(errorMessage, on: context)
                context.logger.warning("\(errorMessage)")
                continue
            }

            let shouldSend = await suspendedServersService.shouldSend(to: sharedInboxUrl.host, basedOn: suspendedServers)
            guard shouldSend else {
                try? await eventItem.suspended(on: context)
                context.logger.warning("Sending unfavourite skipped for suspended host: '\(sharedInboxUrl.host ?? "<unknown>")'.")
                continue
            }

            // Prepare ActivityPub client.
            context.logger.info("[\(index + 1)/\(eventItemsToProceed.count)] Sending unfavourite: '\(statusFavouriteId)' to shared inbox: '\(sharedInboxUrl.absoluteString)'.")
            let activityPubClient = ActivityPubClient(privatePemKey: privateKey, userAgent: Constants.userAgent, host: sharedInboxUrl.host)

            do {
                // Send status unfavourite via network to remote server.
                try await activityPubClient.unlike(statusFavouriteId: statusFavouriteId,
                                                   activityPubStatusId: status.activityPubId,
                                                   activityPubProfile: user.activityPubProfile,
                                                   on: sharedInboxUrl)

                // Mark event item as finished successfully.
                try? await eventItem.success(on: context)
                try? await suspendedServersService.registerSuccess(for: sharedInboxUrl.host, on: context)
            } catch {
                // Mark event item as finished with error.
                try? await eventItem.error("\(error)", on: context)
                try? await suspendedServersService.registerConnectionError(for: sharedInboxUrl.host, error: error, on: context)
                context.logger.warning("Sending unfavourite to shared inbox error. Shared inbox url: \(sharedInboxUrl). Error: \(error).")
            }
        }

        // Mark event as finished successfully.
        let hasFailedEvents = statusActivityPubEvent.statusActivityPubEventItems.contains(where: { $0.isSuccess == false || $0.isSuspended == true })
        try await statusActivityPubEvent.success(result: hasFailedEvents ? .finishedWithErrors : .finished, on: context)
    }

    public func announce(statusActivityPubEvent: StatusActivityPubEvent, activityPubReblog: ActivityPubReblogDto?, on context: ExecutionContext) async throws {
        try await statusActivityPubEvent.start(on: context)

        // Private key is required for sending ActivityPub request.
        guard let privateKey = try await self.getPrivateKey(statusActivityPubEvent: statusActivityPubEvent, on: context) else {
            return
        }

        let suspendedServersService = context.services.suspendedServersService

        guard let status = try await self.getStatus(statusActivityPubEvent: statusActivityPubEvent, on: context) else {
            return
        }

        guard let activityPubReblog else {
            let errorMessage = "Status announce: '\(status.stringId() ?? "")' cannot be send to shared inbox. Missing announce data."

            // Mark event as finished with error.
            try await statusActivityPubEvent.error(errorMessage, on: context)

            context.logger.warning("\(errorMessage)")
            return
        }

        // Download suspended servers list.
        let suspendedServers = await suspendedServersService.getSnapshot(on: context)

        // Try to send update only to hosts which we didn't sent update yet.
        let eventItemsToProceed = statusActivityPubEvent.statusActivityPubEventItems.filter { $0.isSuccess == nil }

        // Send updated note to all inboxes.
        for (index, eventItem) in eventItemsToProceed.enumerated() {
            try await eventItem.start(on: context)

            // Translate string into URL.
            guard let sharedInboxUrl = URL(string: eventItem.url) else {
                let errorMessage = "Announce: '\(activityPubReblog.activityPubStatusId)' (orginal status id: '\(status.stringId() ?? "")') cannot be send to shared inbox url: '\(eventItem.url)'. Incorrect url."

                try? await eventItem.error(errorMessage, on: context)
                context.logger.warning("\(errorMessage)")
                continue
            }

            let shouldSend = await suspendedServersService.shouldSend(to: sharedInboxUrl.host, basedOn: suspendedServers)
            guard shouldSend else {
                try? await eventItem.suspended(on: context)
                context.logger.warning("Sending announce skipped for suspended host: '\(sharedInboxUrl.host ?? "<unknown>")'.")
                continue
            }

            // Prepare ActivityPub client.
            context.logger.info("[\(index + 1)/\(eventItemsToProceed.count)] Sending announce: '\(activityPubReblog.activityPubStatusId)' (orginal status id: '\(status.stringId() ?? "")') to shared inbox: '\(sharedInboxUrl.absoluteString)'.")
            let activityPubClient = ActivityPubClient(privatePemKey: privateKey, userAgent: Constants.userAgent, host: sharedInboxUrl.host)

            do {
                // Send status announce via network to remote server.
                try await activityPubClient.announce(activityPubStatusId: activityPubReblog.activityPubStatusId,
                                                     activityPubProfile: activityPubReblog.activityPubProfile,
                                                     published: activityPubReblog.published,
                                                     activityPubReblogProfile: activityPubReblog.activityPubReblogProfile,
                                                     activityPubReblogStatusId: activityPubReblog.activityPubReblogStatusId,
                                                     on: sharedInboxUrl)

                // Mark event item as finished successfully.
                try? await eventItem.success(on: context)
                try? await suspendedServersService.registerSuccess(for: sharedInboxUrl.host, on: context)
            } catch {
                // Mark event item as finished with error.
                try? await eventItem.error("\(error)", on: context)
                try? await suspendedServersService.registerConnectionError(for: sharedInboxUrl.host, error: error, on: context)
                context.logger.warning("Sending announce to shared inbox error. Shared inbox url: \(sharedInboxUrl). Error: \(error).")
            }
        }

        // Mark event as finished successfully.
        let hasFailedEvents = statusActivityPubEvent.statusActivityPubEventItems.contains(where: { $0.isSuccess == false || $0.isSuspended == true })
        try await statusActivityPubEvent.success(result: hasFailedEvents ? .finishedWithErrors : .finished, on: context)
    }

    public func unannounce(statusActivityPubEvent: StatusActivityPubEvent, activityPubUnreblog: ActivityPubUnreblogDto?, on context: ExecutionContext) async throws {
        try await statusActivityPubEvent.start(on: context)

        // Private key is required for sending ActivityPub request.
        guard let privateKey = try await self.getPrivateKey(statusActivityPubEvent: statusActivityPubEvent, on: context) else {
            return
        }

        let suspendedServersService = context.services.suspendedServersService

        guard let status = try await self.getStatus(statusActivityPubEvent: statusActivityPubEvent, on: context) else {
            return
        }

        guard let activityPubUnreblog else {
            let errorMessage = "Status unannounce: '\(status.stringId() ?? "")' cannot be send to shared inbox. Missing unannounce data."

            // Mark event as finished with error.
            try await statusActivityPubEvent.error(errorMessage, on: context)

            context.logger.warning("\(errorMessage)")
            return
        }

        // Download suspended servers list.
        let suspendedServers = await suspendedServersService.getSnapshot(on: context)

        // Try to send update only to hosts which we didn't sent update yet.
        let eventItemsToProceed = statusActivityPubEvent.statusActivityPubEventItems.filter { $0.isSuccess == nil }

        // Send updated note to all inboxes.
        for (index, eventItem) in eventItemsToProceed.enumerated() {
            try await eventItem.start(on: context)

            // Translate string into URL.
            guard let sharedInboxUrl = URL(string: eventItem.url) else {
                let errorMessage = "Unannounce: '\(activityPubUnreblog.activityPubStatusId)' (orginal status id: '\(status.stringId() ?? "")') cannot be send to shared inbox url: '\(eventItem.url)'. Incorrect url."

                try? await eventItem.error(errorMessage, on: context)
                context.logger.warning("\(errorMessage)")
                continue
            }

            let shouldSend = await suspendedServersService.shouldSend(to: sharedInboxUrl.host, basedOn: suspendedServers)
            guard shouldSend else {
                try? await eventItem.suspended(on: context)
                context.logger.warning("Sending unannounce skipped for suspended host: '\(sharedInboxUrl.host ?? "<unknown>")'.")
                continue
            }

            // Prepare ActivityPub client.
            context.logger.info("[\(index + 1)/\(eventItemsToProceed.count)] Sending unannounce: '\(activityPubUnreblog.activityPubStatusId)' (orginal status id: '\(status.stringId() ?? "")') to shared inbox: '\(sharedInboxUrl.absoluteString)'.")
            let activityPubClient = ActivityPubClient(privatePemKey: privateKey, userAgent: Constants.userAgent, host: sharedInboxUrl.host)

            do {
                // Send status announce via network to remote server.
                try await activityPubClient.unannounce(activityPubStatusId: activityPubUnreblog.activityPubStatusId,
                                                       activityPubProfile: activityPubUnreblog.activityPubProfile,
                                                       published: activityPubUnreblog.published,
                                                       activityPubReblogProfile: activityPubUnreblog.activityPubReblogProfile,
                                                       activityPubReblogStatusId: activityPubUnreblog.activityPubReblogStatusId,
                                                       on: sharedInboxUrl)

                // Mark event item as finished successfully.
                try? await eventItem.success(on: context)
                try? await suspendedServersService.registerSuccess(for: sharedInboxUrl.host, on: context)
            } catch {
                // Mark event item as finished with error.
                try? await eventItem.error("\(error)", on: context)
                try? await suspendedServersService.registerConnectionError(for: sharedInboxUrl.host, error: error, on: context)
                context.logger.warning("Sending unannounce to shared inbox error. Shared inbox url: \(sharedInboxUrl). Error: \(error).")
            }
        }

        // Mark event as finished successfully.
        let hasFailedEvents = statusActivityPubEvent.statusActivityPubEventItems.contains(where: { $0.isSuccess == false || $0.isSuspended == true })
        try await statusActivityPubEvent.success(result: hasFailedEvents ? .finishedWithErrors : .finished, on: context)
    }

    public func pin(statusActivityPubEvent: StatusActivityPubEvent, on context: ExecutionContext) async throws {
        try await statusActivityPubEvent.start(on: context)

        // Private key is required for sending ActivityPub request.
        guard let privateKey = try await self.getPrivateKey(statusActivityPubEvent: statusActivityPubEvent, on: context) else {
            return
        }

        let suspendedServersService = context.services.suspendedServersService
        let snowflakeService = context.services.snowflakeService

        guard let status = try await self.getStatus(statusActivityPubEvent: statusActivityPubEvent, on: context) else {
            return
        }

        let user = statusActivityPubEvent.user
        let featuredCollection = user.featured ?? "\(user.activityPubProfile)/featured"

        // Download suspended servers list.
        let suspendedServers = await suspendedServersService.getSnapshot(on: context)

        // Try to send update only to hosts which we didn't sent update yet.
        let eventItemsToProceed = statusActivityPubEvent.statusActivityPubEventItems.filter { $0.isSuccess == nil }

        // Send Add activity to all inboxes.
        for (index, eventItem) in eventItemsToProceed.enumerated() {
            try await eventItem.start(on: context)

            guard let inboxUrl = URL(string: eventItem.url) else {
                let errorMessage = "Pin: '\(status.stringId() ?? "")' cannot be send to shared inbox url: '\(eventItem.url)'. Incorrect url."

                try? await eventItem.error(errorMessage, on: context)
                context.logger.warning("\(errorMessage)")
                continue
            }

            let shouldSend = await suspendedServersService.shouldSend(to: inboxUrl.host, basedOn: suspendedServers)
            guard shouldSend else {
                try? await eventItem.suspended(on: context)
                context.logger.warning("Sending pin skipped for suspended host: '\(inboxUrl.host ?? "<unknown>")'.")
                continue
            }

            context.logger.info("[\(index + 1)/\(eventItemsToProceed.count)] Sending pin: '\(status.stringId() ?? "")' to shared inbox: '\(inboxUrl.absoluteString)'.")
            let activityPubClient = ActivityPubClient(privatePemKey: privateKey, userAgent: Constants.userAgent, host: inboxUrl.host)
            let requestId = snowflakeService.generate()

            do {
                try await activityPubClient.addToFeatured(objectId: status.activityPubId,
                                                          actorId: user.activityPubProfile,
                                                          targetId: featuredCollection,
                                                          on: inboxUrl,
                                                          withId: requestId)

                try? await eventItem.success(on: context)
                try? await suspendedServersService.registerSuccess(for: inboxUrl.host, on: context)
            } catch {
                try? await eventItem.error("\(error)", on: context)
                try? await suspendedServersService.registerConnectionError(for: inboxUrl.host, error: error, on: context)
                context.logger.warning("Sending pin to shared inbox error. Shared inbox url: \(inboxUrl). Error: \(error).")
            }
        }

        // Mark event as finished successfully.
        let hasFailedEvents = statusActivityPubEvent.statusActivityPubEventItems.contains(where: { $0.isSuccess == false || $0.isSuspended == true })
        try await statusActivityPubEvent.success(result: hasFailedEvents ? .finishedWithErrors : .finished, on: context)
    }

    public func unpin(statusActivityPubEvent: StatusActivityPubEvent, on context: ExecutionContext) async throws {
        try await statusActivityPubEvent.start(on: context)

        // Private key is required for sending ActivityPub request.
        guard let privateKey = try await self.getPrivateKey(statusActivityPubEvent: statusActivityPubEvent, on: context) else {
            return
        }

        let suspendedServersService = context.services.suspendedServersService
        let snowflakeService = context.services.snowflakeService

        guard let status = try await self.getStatus(statusActivityPubEvent: statusActivityPubEvent, on: context) else {
            return
        }

        let user = statusActivityPubEvent.user
        let featuredCollection = user.featured ?? "\(user.activityPubProfile)/featured"

        // Download suspended servers list.
        let suspendedServers = await suspendedServersService.getSnapshot(on: context)

        // Try to send update only to hosts which we didn't sent update yet.
        let eventItemsToProceed = statusActivityPubEvent.statusActivityPubEventItems.filter { $0.isSuccess == nil }

        // Send Remove activity to all inboxes.
        for (index, eventItem) in eventItemsToProceed.enumerated() {
            try await eventItem.start(on: context)

            guard let inboxUrl = URL(string: eventItem.url) else {
                let errorMessage = "Unpin: '\(status.stringId() ?? "")' cannot be send to shared inbox url: '\(eventItem.url)'. Incorrect url."

                try? await eventItem.error(errorMessage, on: context)
                context.logger.warning("\(errorMessage)")
                continue
            }

            let shouldSend = await suspendedServersService.shouldSend(to: inboxUrl.host, basedOn: suspendedServers)
            guard shouldSend else {
                try? await eventItem.suspended(on: context)
                context.logger.warning("Sending unpin skipped for suspended host: '\(inboxUrl.host ?? "<unknown>")'.")
                continue
            }

            context.logger.info("[\(index + 1)/\(eventItemsToProceed.count)] Sending unpin: '\(status.stringId() ?? "")' to shared inbox: '\(inboxUrl.absoluteString)'.")
            let activityPubClient = ActivityPubClient(privatePemKey: privateKey, userAgent: Constants.userAgent, host: inboxUrl.host)
            let requestId = snowflakeService.generate()

            do {
                try await activityPubClient.removeFromFeatured(objectId: status.activityPubId,
                                                               actorId: user.activityPubProfile,
                                                               targetId: featuredCollection,
                                                               on: inboxUrl,
                                                               withId: requestId)

                try? await eventItem.success(on: context)
                try? await suspendedServersService.registerSuccess(for: inboxUrl.host, on: context)
            } catch {
                try? await eventItem.error("\(error)", on: context)
                try? await suspendedServersService.registerConnectionError(for: inboxUrl.host, error: error, on: context)
                context.logger.warning("Sending unpin to shared inbox error. Shared inbox url: \(inboxUrl). Error: \(error).")
            }
        }

        // Mark event as finished successfully.
        let hasFailedEvents = statusActivityPubEvent.statusActivityPubEventItems.contains(where: { $0.isSuccess == false || $0.isSuspended == true })
        try await statusActivityPubEvent.success(result: hasFailedEvents ? .finishedWithErrors : .finished, on: context)
    }

    private func getStatus(statusActivityPubEvent: StatusActivityPubEvent, on context: ExecutionContext) async throws -> Status? {
        let statusesService = context.services.statusesService
        let operation = statusActivityPubEvent.type

        guard let status = try await statusesService.get(id: statusActivityPubEvent.status.requireID(), on: context.db) else {
            let errorMessage = "Status \(operation): '\(statusActivityPubEvent.$status.id)' cannot be downloaded from database."

            // Mark event as finished with error.
            try await statusActivityPubEvent.error(errorMessage, on: context)

            context.logger.warning("\(errorMessage)")
            return nil
        }

        return status
    }

    private func getStatusHistory(statusActivityPubEvent: StatusActivityPubEvent, on context: ExecutionContext) async throws -> StatusHistory? {
        let status = statusActivityPubEvent.status

        guard let statusHistory = try await StatusHistory.query(on: context.db)
            .filter(\.$orginalStatus.$id == status.requireID())
            .sort(\.$createdAt, .descending)
            .first() else {
            let errorMessage = "Status history cannot be downloaded from database for status '\(status.stringId() ?? "")'."

            // Mark event as finished with error.
            try await statusActivityPubEvent.error(errorMessage, on: context)

            context.logger.warning("\(errorMessage)")
            return nil
        }

        return statusHistory
    }

    private func getPrivateKey(statusActivityPubEvent: StatusActivityPubEvent, on context: ExecutionContext) async throws -> String? {
        let user = statusActivityPubEvent.user
        let status = statusActivityPubEvent.status
        let operation = statusActivityPubEvent.type

        guard let privateKey = try await User.query(on: context.application.db).filter(\.$id == user.requireID()).first()?.privateKey else {
            let errorMessage = "Status \(operation): '\(status.stringId() ?? "")' cannot be send to shared inbox. Missing private key for user '\(status.user.stringId() ?? "")'."

            // Mark event as finished with error.
            try await statusActivityPubEvent.error(errorMessage, on: context)

            context.logger.warning("\(errorMessage)")
            return nil
        }

        return privateKey
    }
}
