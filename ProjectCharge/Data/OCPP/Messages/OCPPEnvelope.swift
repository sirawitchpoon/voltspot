import Foundation

/// Standard OCPP-J errorCode values (spec section 4.4).
enum OCPPCallErrorCode: String, Codable, Sendable {
    case notImplemented = "NotImplemented"
    case notSupported = "NotSupported"
    case internalError = "InternalError"
    case protocolError = "ProtocolError"
    case securityError = "SecurityError"
    case formationViolation = "FormationViolation"
    case propertyConstraintViolation = "PropertyConstraintViolation"
    case occurenceConstraintViolation = "OccurenceConstraintViolation"
    case typeConstraintViolation = "TypeConstraintViolation"
    case genericError = "GenericError"
}

/// OCPP-J wire envelope. Encoded/decoded as a heterogeneous JSON array.
///
/// - Call:        `[2, "<UniqueId>", "<Action>", {payload}]`
/// - CallResult:  `[3, "<UniqueId>", {payload}]`
/// - CallError:   `[4, "<UniqueId>", "<ErrorCode>", "<ErrorDescription>", {ErrorDetails}]`
///
/// The payload is held as raw `Data` so the transport layer can stay
/// payload-agnostic; `OCPPClient` decodes/encodes the action-specific
/// `Codable` types around this envelope.
enum OCPPEnvelope: Sendable {
    case call(uniqueId: String, action: String, payload: Data)
    case callResult(uniqueId: String, payload: Data)
    case callError(uniqueId: String, code: OCPPCallErrorCode, description: String, details: Data)
}

extension OCPPEnvelope: Codable {

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let typeRaw = try container.decode(Int.self)
        guard let type = OCPPMessageType(rawValue: typeRaw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown OCPP MessageTypeId: \(typeRaw)"
            )
        }
        let uniqueId = try container.decode(String.self)
        switch type {
        case .call:
            let action = try container.decode(String.self)
            let payload = try Self.decodeRawJSON(from: &container)
            self = .call(uniqueId: uniqueId, action: action, payload: payload)
        case .callResult:
            let payload = try Self.decodeRawJSON(from: &container)
            self = .callResult(uniqueId: uniqueId, payload: payload)
        case .callError:
            let codeRaw = try container.decode(String.self)
            let code = OCPPCallErrorCode(rawValue: codeRaw) ?? .genericError
            let description = try container.decode(String.self)
            let details = (try? Self.decodeRawJSON(from: &container)) ?? Data("{}".utf8)
            self = .callError(uniqueId: uniqueId, code: code, description: description, details: details)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        switch self {
        case let .call(uniqueId, action, payload):
            try container.encode(OCPPMessageType.call.rawValue)
            try container.encode(uniqueId)
            try container.encode(action)
            try Self.encodeRawJSON(payload, to: &container)
        case let .callResult(uniqueId, payload):
            try container.encode(OCPPMessageType.callResult.rawValue)
            try container.encode(uniqueId)
            try Self.encodeRawJSON(payload, to: &container)
        case let .callError(uniqueId, code, description, details):
            try container.encode(OCPPMessageType.callError.rawValue)
            try container.encode(uniqueId)
            try container.encode(code.rawValue)
            try container.encode(description)
            try Self.encodeRawJSON(details, to: &container)
        }
    }

    private static func decodeRawJSON(from container: inout UnkeyedDecodingContainer) throws -> Data {
        // Decode as JSONValue tree, then re-serialize to canonical Data.
        let value = try container.decode(JSONValue.self)
        return try JSONEncoder().encode(value)
    }

    private static func encodeRawJSON(_ data: Data, to container: inout UnkeyedEncodingContainer) throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        try container.encode(value)
    }
}

/// Tiny dynamic JSON tree used so we can shuttle arbitrary payloads through
/// `Codable` without committing to a static schema at the envelope layer.
enum JSONValue: Codable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let v = try? c.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? c.decode(Int.self) {
            self = .int(v)
        } else if let v = try? c.decode(Double.self) {
            self = .double(v)
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else if let v = try? c.decode([JSONValue].self) {
            self = .array(v)
        } else if let v = try? c.decode([String: JSONValue].self) {
            self = .object(v)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}
