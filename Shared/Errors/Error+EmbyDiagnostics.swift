//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

extension Error {

    var embyDisplayDescription: String {
        #if DEBUG
        embyDiagnosticDescription
        #else
        localizedDescription
        #endif
    }

    var embyDiagnosticDescription: String {
        guard let decodingError = self as? DecodingError else {
            return localizedDescription
        }

        switch decodingError {
        case let .typeMismatch(type, context):
            return "typeMismatch \(type) at \(context.embyCodingPath): \(context.debugDescription)"
        case let .valueNotFound(type, context):
            return "valueNotFound \(type) at \(context.embyCodingPath): \(context.debugDescription)"
        case let .keyNotFound(key, context):
            return "keyNotFound \(key.stringValue) at \(context.embyCodingPath): \(context.debugDescription)"
        case let .dataCorrupted(context):
            return "dataCorrupted at \(context.embyCodingPath): \(context.debugDescription)"
        @unknown default:
            return String(reflecting: self)
        }
    }
}

private extension DecodingError.Context {

    var embyCodingPath: String {
        let path = codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? "<root>" : path
    }
}
