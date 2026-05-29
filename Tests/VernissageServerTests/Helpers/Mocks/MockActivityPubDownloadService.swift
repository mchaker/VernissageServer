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

    func downloadRemoteUserIfMissing(userName: String, on context: VernissageServer.ExecutionContext) async throws -> VernissageServer.User? {
        return nil
    }

    func downloadRemoteUserIfNeeded(activityPubProfile: String, on context: VernissageServer.ExecutionContext) async throws -> VernissageServer.User? {
        let activityPubDownloadService = ActivityPubDownloadService()
        return try await activityPubDownloadService.downloadRemoteUserIfNeeded(activityPubProfile: activityPubProfile, on: context)
    }

    func downloadPerson(activityPubProfile: String, on context: VernissageServer.ExecutionContext) async throws -> ActivityPubKit.PersonDto {
        let activityPubDownloadService = ActivityPubDownloadService()
        return try await activityPubDownloadService.downloadPerson(activityPubProfile: activityPubProfile, on: context)
    }

    func refreshRemoteUser(activityPubProfile: String, on context: VernissageServer.ExecutionContext) async throws -> VernissageServer.User? {
        let activityPubDownloadService = ActivityPubDownloadService()
        return try await activityPubDownloadService.refreshRemoteUser(activityPubProfile: activityPubProfile, on: context)
    }

    func resolveActivityPubProfile(userName: String, on context: VernissageServer.ExecutionContext) async -> String? {
        let name = userName.split(separator: "@").first
        let domain = userName.split(separator: "@").last

        return "https://\(domain ?? "example.com")/users/\(name ?? "user")}"
    }

    func resolveActivityPubProfile(userName: String, baseUrl: URL, on context: VernissageServer.ExecutionContext) async -> String? {
        let activityPubDownloadService = ActivityPubDownloadService()
        return await activityPubDownloadService.resolveActivityPubProfile(userName: userName, baseUrl: baseUrl, on: context)
    }
}
