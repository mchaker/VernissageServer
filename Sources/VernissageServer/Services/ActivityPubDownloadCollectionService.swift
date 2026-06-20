//
//  https://mczachurski.dev
//  Copyright © 2026 Marcin Czachurski and the repository contributors.
//  Licensed under the Apache License 2.0.
//

import Vapor
import Fluent
import Queues
import ActivityPubKit
import SwiftSoup

extension Application.Services {
    struct ActivityPubDownloadCollectionServiceKey: StorageKey {
        typealias Value = ActivityPubDownloadCollectionServiceType
    }

    var activityPubDownloadCollectionService: ActivityPubDownloadCollectionServiceType {
        get {
            self.application.storage[ActivityPubDownloadCollectionServiceKey.self] ?? ActivityPubDownloadCollectionService()
        }
        nonmutating set {
            self.application.storage[ActivityPubDownloadCollectionServiceKey.self] = newValue
        }
    }
}

@_documentation(visibility: private)
protocol ActivityPubDownloadCollectionServiceType: Sendable {

    /// Downloads a remote ActivityPub featured collection and returns the referenced status identifiers.
    ///
    /// The method signs the request with the default system user's private key and follows `OrderedCollection`
    /// pagination through the first page and subsequent `next` links. Embedded `Note` objects are returned
    /// together with their ActivityPub IDs so callers can create local statuses from already downloaded data
    /// before falling back to downloading individual statuses.
    ///
    /// - Parameters:
    ///   - featuredUrl: The ActivityPub featured collection URL to download.
    ///   - context: The execution context providing services and database access.
    /// - Returns: A set of featured status ActivityPub IDs and embedded notes keyed by their ActivityPub IDs.
    /// - Throws: Configuration, network, or decoding errors when the collection cannot be downloaded.
    func downloadFeaturedCollection(featuredUrl: URL, on context: ExecutionContext) async throws -> (statusIds: Set<String>, statusNotes: [String: NoteDto])
}

final class ActivityPubDownloadCollectionService: ActivityPubDownloadCollectionServiceType {

    public func downloadFeaturedCollection(featuredUrl: URL, on context: ExecutionContext) async throws -> (statusIds: Set<String>, statusNotes: [String: NoteDto]) {
        var featuredStatusIds = Set<String>()
        var featuredStatusNotes: [String: NoteDto] = [:]
        var visitedPageUrls = Set<String>()
        var nextPageUrl: URL? = featuredUrl
        var firstPage = true
        
        let usersService = context.services.usersService
        guard let defaultSystemUser = try await usersService.getDefaultSystemUser(on: context.db) else {
            throw ActivityPubError.missingInstanceAdminAccount
        }

        guard let privateKey = defaultSystemUser.privateKey else {
            throw ActivityPubError.missingInstanceAdminPrivateKey
        }

        let activityPubClient = ActivityPubClient(privatePemKey: privateKey, userAgent: Constants.userAgent, host: featuredUrl.host)

        while let currentPageUrl = nextPageUrl {
            // We have to prevent loops (when remote will return same url in next property).
            let pageKey = currentPageUrl.absoluteString
            if visitedPageUrls.contains(pageKey) {
                context.logger.warning("Featured collection pagination loop detected for URL: '\(pageKey)'.")
                break
            }

            // Download ordered collection.
            visitedPageUrls.insert(pageKey)
            let collectionDto = try await activityPubClient.featuredCollection(url: currentPageUrl, activityPubProfile: defaultSystemUser.activityPubProfile)

            var orderedObjects: [ObjectDto] = []
            var firstUrlString: String?
            var nextUrlString: String?

            // Add objects to the private variable.
            switch collectionDto {
            case .orderedCollection(let orderedCollection):
                orderedObjects = orderedCollection.orderedItems?.objects() ?? []
                firstUrlString = orderedCollection.first
            case .orderedCollectionPage(let orderedCollectionPage):
                orderedObjects = orderedCollectionPage.orderedItems.objects()
                nextUrlString = orderedCollectionPage.next
            }

            // Iterate via objects and add to id's or entities arrays.
            for orderedObject in orderedObjects {
                featuredStatusIds.insert(orderedObject.id)
                if let noteDto = orderedObject.object as? NoteDto {
                    featuredStatusNotes[orderedObject.id] = noteDto
                }
            }

            // Calculate url to get next data portion.
            if firstPage, let firstUrlString {
                nextPageUrl = self.resolveCollectionPageUrl(firstUrlString, relativeTo: currentPageUrl)
            } else if let nextUrlString {
                nextPageUrl = self.resolveCollectionPageUrl(nextUrlString, relativeTo: currentPageUrl)
            } else {
                nextPageUrl = nil
            }

            firstPage = false
        }

        return (statusIds: featuredStatusIds, statusNotes: featuredStatusNotes)
    }

    private func resolveCollectionPageUrl(_ value: String, relativeTo baseUrl: URL) -> URL? {
        if let url = URL(string: value), url.scheme != nil {
            return url
        }

        return URL(string: value, relativeTo: baseUrl)?.absoluteURL
    }
}
