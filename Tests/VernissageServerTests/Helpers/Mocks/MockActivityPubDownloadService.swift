//
//  https://mczachurski.dev
//  Copyright © 2024 Marcin Czachurski and the repository contributors.
//  Licensed under the Apache License 2.0.
//

@testable import VernissageServer
import VaporTesting
import ActivityPubKit
import Queues

final class MockActivityPubDownloadUserService: ActivityPubDownloadUserServiceType {
    func downloadPerson(activityPubProfile: String, on context: VernissageServer.ExecutionContext) async throws -> ActivityPubKit.PersonDto {
        let activityPubDownloadUserService = ActivityPubDownloadUserService()
        return try await activityPubDownloadUserService.downloadPerson(activityPubProfile: activityPubProfile, on: context)
    }

    func downloadIfMissing(userName: String, on context: VernissageServer.ExecutionContext) async throws -> VernissageServer.User? {
        return nil
    }

    func downloadIfNeeded(activityPubProfile: String, on context: VernissageServer.ExecutionContext) async throws -> VernissageServer.User? {
        let activityPubDownloadUserService = ActivityPubDownloadUserService()
        return try await activityPubDownloadUserService.downloadIfNeeded(activityPubProfile: activityPubProfile, on: context)
    }

    func refreshRemoteUser(activityPubProfile: String, on context: VernissageServer.ExecutionContext) async throws -> VernissageServer.User? {
        let activityPubDownloadUserService = ActivityPubDownloadUserService()
        return try await activityPubDownloadUserService.refreshRemoteUser(activityPubProfile: activityPubProfile, on: context)
    }

    func resolveActivityPubProfile(userName: String, on context: VernissageServer.ExecutionContext) async -> String? {
        let name = userName.split(separator: "@").first
        let domain = userName.split(separator: "@").last

        return "https://\(domain ?? "example.com")/users/\(name ?? "user")}"
    }

    func resolveActivityPubProfile(userName: String, baseUrl: URL, on context: VernissageServer.ExecutionContext) async -> String? {
        let activityPubDownloadUserService = ActivityPubDownloadUserService()
        return await activityPubDownloadUserService.resolveActivityPubProfile(userName: userName, baseUrl: baseUrl, on: context)
    }
}
