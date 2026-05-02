import XCTest
@testable import Voltspot

final class OCPPCodableTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func testBootNotificationRequestRoundTrip() throws {
        let original = BootNotificationRequest(
            chargePointVendor: "Acme",
            chargePointModel: "X1",
            chargePointSerialNumber: "SN-001",
            chargeBoxSerialNumber: nil,
            firmwareVersion: "1.0.0",
            iccid: nil,
            imsi: nil,
            meterType: nil,
            meterSerialNumber: nil
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(BootNotificationRequest.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testCallEnvelopeWireFormat() throws {
        let payload = try encoder.encode(
            BootNotificationRequest(
                chargePointVendor: "Acme",
                chargePointModel: "X1",
                chargePointSerialNumber: nil,
                chargeBoxSerialNumber: nil,
                firmwareVersion: nil,
                iccid: nil,
                imsi: nil,
                meterType: nil,
                meterSerialNumber: nil
            )
        )
        let envelope = OCPPEnvelope.call(
            uniqueId: "abc-1",
            action: OCPPAction.bootNotification.rawValue,
            payload: payload
        )

        let data = try encoder.encode(envelope)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [Any])

        XCTAssertEqual(json.count, 4)
        XCTAssertEqual(json[0] as? Int, OCPPMessageType.call.rawValue)
        XCTAssertEqual(json[1] as? String, "abc-1")
        XCTAssertEqual(json[2] as? String, "BootNotification")
        XCTAssertNotNil(json[3] as? [String: Any])
    }

    func testCallResultRoundTrip() throws {
        // Construct the wire form a Central System would send back.
        let now = Date()
        let formatter = ISO8601DateFormatter()
        let json: [Any] = [
            OCPPMessageType.callResult.rawValue,
            "abc-1",
            [
                "status": "Accepted",
                "currentTime": formatter.string(from: now),
                "interval": 30,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let envelope = try decoder.decode(OCPPEnvelope.self, from: data)
        guard case let .callResult(uniqueId, payload) = envelope else {
            return XCTFail("Expected CallResult")
        }
        XCTAssertEqual(uniqueId, "abc-1")

        let response = try decoder.decode(BootNotificationResponse.self, from: payload)
        XCTAssertEqual(response.status, .accepted)
        XCTAssertEqual(response.interval, 30)
    }

    func testCallErrorDecode() throws {
        let json: [Any] = [
            OCPPMessageType.callError.rawValue,
            "abc-2",
            "InternalError",
            "Boom",
            ["context": "test"],
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let envelope = try decoder.decode(OCPPEnvelope.self, from: data)
        guard case let .callError(uniqueId, code, description, _) = envelope else {
            return XCTFail("Expected CallError")
        }
        XCTAssertEqual(uniqueId, "abc-2")
        XCTAssertEqual(code, .internalError)
        XCTAssertEqual(description, "Boom")
    }

    func testOCPPVersionSubprotocol() {
        XCTAssertEqual(OCPPVersion.v16J.subprotocolHeader, "ocpp1.6")
    }
}
