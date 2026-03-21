//
//  https://mczachurski.dev
//  Copyright © 2024 Marcin Czachurski and the repository contributors.
//  Licensed under the Apache License 2.0.
//

import Vapor

struct UserMuteRequestDto {
    var muteStatuses: Bool
    var muteReblogs: Bool
    var muteNotifications: Bool
    var muteEnd: Date?
    var removeStatusesFromTimeline: Bool?
    var removeReblogsFromTimeline: Bool?
}

extension UserMuteRequestDto: Content { }
