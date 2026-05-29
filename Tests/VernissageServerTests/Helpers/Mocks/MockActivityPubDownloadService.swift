//
//  https://mczachurski.dev
//  Copyright © 2024 Marcin Czachurski and the repository contributors.
//  Licensed under the Apache License 2.0.
//

@testable import VernissageServer
import VaporTesting
import ActivityPubKit
import Queues

final class MockActivityPubDownloadService: ActivityPubDownloadServiceType {
    func downloadStatus(activityPubId: String, on context: VernissageServer.ExecutionContext) async throws -> VernissageServer.Status {
        let activityPubDownloadService = ActivityPubDownloadService()
        return try await activityPubDownloadService.downloadStatus(activityPubId: activityPubId, on: context)
    }

    func downloadStatusSuppressingErrors(activityPubId: String, on context: VernissageServer.ExecutionContext) async throws -> VernissageServer.Status? {
        let activityPubDownloadService = ActivityPubDownloadService()
        return try await activityPubDownloadService.downloadStatusSuppressingErrors(activityPubId: activityPubId, on: context)
    }

    func getRemoteUserFromLocalDatabaseFirst(userName: String, on context: VernissageServer.ExecutionContext) async throws -> VernissageServer.User? {
        return nil
    }

    func getRemoteUserWithCacheVerification(activityPubProfile: String, on context: VernissageServer.ExecutionContext) async throws -> VernissageServer.User? {
        let activityPubDownloadService = ActivityPubDownloadService()
        return try await activityPubDownloadService.getRemoteUserWithCacheVerification(activityPubProfile: activityPubProfile, on: context)
    }

    func downloadPerson(activityPubProfile: String, on context: VernissageServer.ExecutionContext) async throws -> ActivityPubKit.PersonDto {
        let activityPubDownloadService = ActivityPubDownloadService()
        return try await activityPubDownloadService.downloadPerson(activityPubProfile: activityPubProfile, on: context)
    }

    func refreshRemoteUser(activityPubProfile: String, on context: VernissageServer.ExecutionContext) async throws -> VernissageServer.User? {
        let activityPubDownloadService = ActivityPubDownloadService()
        return try await activityPubDownloadService.refreshRemoteUser(activityPubProfile: activityPubProfile, on: context)
    }

    func getRemoteActivityPubProfile(userName: String, on context: VernissageServer.ExecutionContext) async -> String? {
        let name = userName.split(separator: "@").first
        let domain = userName.split(separator: "@").last

        return "https://\(domain ?? "example.com")/users/\(name ?? "user")}"
    }

    func getActivityPubProfile(userName: String, baseUrl: URL, on context: VernissageServer.ExecutionContext) async -> String? {
        let activityPubDownloadService = ActivityPubDownloadService()
        return await activityPubDownloadService.getActivityPubProfile(userName: userName, baseUrl: baseUrl, on: context)
    }
}
