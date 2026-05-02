import Foundation

// Schema: Authorize.json
struct AuthorizeRequest: Codable, Sendable, Equatable {
    let idTag: String
}

// Schema: AuthorizeResponse.json
struct AuthorizeResponse: Codable, Sendable, Equatable {
    let idTagInfo: OCPPIdTagInfo
}
