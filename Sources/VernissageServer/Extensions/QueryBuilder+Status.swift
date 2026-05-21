//
//  https://mczachurski.dev
//  Copyright © 2024 Marcin Czachurski and the repository contributors.
//  Licensed under the Apache License 2.0.
//

import Vapor
import Fluent
import SQLKit

extension QueryBuilder<Status> {
    func filter(id: Int64?) -> Self {
        guard let id else {
            return self
        }
        
        return self.filter(\.$id == id)
    }

    func filter(note query: String) -> Self {
        if let sqlDatabase = self.database as? SQLDatabase, sqlDatabase.dialect.name == "postgresql" {
            return self.filter(\.$note, .custom("ILIKE"), "%\(query)%")
        }

        return self.filter(\.$note ~~ query)
    }
}
