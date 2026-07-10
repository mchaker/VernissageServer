//
//  https://mczachurski.dev
//  Copyright © 2026 Marcin Czachurski and the repository contributors.
//  Licensed under the Apache License 2.0.
//

import Vapor
import Foundation
import Fluent
import ActivityPubKit

extension Application.Services {
    struct ActivityPubOutgoingReportServiceKey: StorageKey {
        typealias Value = ActivityPubOutgoingReportServiceType
    }

    var activityPubOutgoingReportService: ActivityPubOutgoingReportServiceType {
        get {
            self.application.storage[ActivityPubOutgoingReportServiceKey.self] ?? ActivityPubOutgoingReportService()
        }
        nonmutating set {
            self.application.storage[ActivityPubOutgoingReportServiceKey.self] = newValue
        }
    }
}

@_documentation(visibility: private)
protocol ActivityPubOutgoingReportServiceType: Sendable {
    /// Sends a local report as an ActivityPub `Flag` activity to the reported user's remote instance.
    ///
    /// The method loads the report with its reported user and optional status from the local database.
    /// Reports are forwarded only when forwarding is enabled and the reported user is remote. The request is
    /// signed with the default system user's private key and delivered to the reported user's shared inbox,
    /// or user inbox when a shared inbox is not available. Missing reports, disabled forwarding, local reported
    /// users, and invalid inboxes are logged and skipped.
    ///
    /// - Parameters:
    ///   - reportId: The local identifier of the report to forward.
    ///   - context: The execution context providing services and database access.
    /// - Throws: Configuration, database, or network errors when the report cannot be forwarded.
    func send(reportId: Int64, on context: ExecutionContext) async throws
}

/// A service for managing reports in the system.
final class ActivityPubOutgoingReportService: ActivityPubOutgoingReportServiceType {
    func send(reportId: Int64, on context: ExecutionContext) async throws {
        guard let report = try await Report.query(on: context.db)
            .with(\.$reportedUser)
            .with(\.$status)
            .filter(\.$id == reportId)
            .first() else {
            context.logger.warning("Report (id: '\(reportId)') cannot be found in database.")
            return
        }
        
        guard report.forward else {
            context.logger.info("Report (id: '\(reportId)') does not have to be forwarded.")
            return
        }
        
        let reportedUser = report.reportedUser
        guard reportedUser.isLocal == false else {
            context.logger.info("Report (id: '\(reportId)') does not have to be forwarded because reported user is local.")
            return
        }
        
        let usersService = context.services.usersService
        guard let defaultSystemUser = try await usersService.getDefaultSystemUser(on: context.db) else {
            throw ActivityPubError.missingInstanceAdminAccount
        }
        
        guard let privateKey = defaultSystemUser.privateKey else {
            throw ActivityPubError.missingInstanceAdminPrivateKey
        }
        
        guard let inbox = reportedUser.sharedInbox ?? reportedUser.userInbox,
              let inboxUrl = URL(string: inbox),
              let inboxHost = inboxUrl.host else {
            context.logger.warning("Report (id: '\(reportId)') cannot be forwarded. Missing or invalid inbox for actor: '\(reportedUser.activityPubProfile)'.")
            return
        }
        
        let reportedObjectIds = self.reportedObjectIds(report: report)
        let content = self.content(report: report)
        let activityPubClient = ActivityPubClient(privatePemKey: privateKey, userAgent: Constants.userAgent, host: inboxHost)
        
        context.logger.info("Sending report (id: '\(reportId)') as Flag to inbox: '\(inboxUrl.absoluteString)'.")
        try await activityPubClient.flag(
            reportedActorId: reportedUser.activityPubProfile,
            reportedObjectIds: reportedObjectIds,
            content: content,
            by: defaultSystemUser.activityPubProfile,
            on: inboxUrl,
            withId: "\(reportId)"
        )
    }
    
    private func reportedObjectIds(report: Report) -> [String] {
        guard let status = report.status else {
            return []
        }

        return [status.activityPubId]
    }
    
    private func content(report: Report) -> String? {
        let category = report.category?.trimmingCharacters(in: .whitespacesAndNewlines)
        let comment = report.comment?.trimmingCharacters(in: .whitespacesAndNewlines)
        let notEmptyCategory = category?.isEmpty == false ? category : nil
        let notEmptyComment = comment?.isEmpty == false ? comment : nil
        
        switch (notEmptyCategory, notEmptyComment) {
        case (.none, .none):
            return nil
        case (.some(let category), .none):
            return category
        case (.none, .some(let comment)):
            return comment
        case (.some(let category), .some(let comment)):
            let separator = category.hasSuffix(".") ? " " : ". "
            return "\(category)\(separator)\(comment)"
        }
    }
}
