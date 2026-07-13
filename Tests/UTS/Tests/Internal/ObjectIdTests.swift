import Foundation
import Testing
@testable import AblyLiveObjects

/// ObjectId generation (`RTO14`).
/// Derived from https://github.com/ably/specification/blob/0a531c79adfc072c6d1441591f2dd838913dfe73/uts/objects/unit/object_id.md
///
/// Pure function, no mocks. The spec's `generateObjectId(type:initialValue:nonce:timestamp:)` maps to
/// the internal `ObjectCreationHelpers.testsOnly_createObjectID` (timestamp is a `Date`; the spec's
/// millisecond value is `Date(timeIntervalSince1970: ms / 1000)`).
@Suite
struct ObjectIdTests {
    private static let timestamp = Date(timeIntervalSince1970: 1_700_000_000) // 1700000000000 ms

    // UTS: objects/unit/RTO14/objectid-format-counter-0
    @Test
    func test_RTO14_objectId_format_for_counter_type() throws {
        let objectId = ObjectCreationHelpers.testsOnly_createObjectID(
            type: "counter",
            initialValue: #"{"counter":{"count":42}}"#,
            nonce: "test-nonce-12345678",
            timestamp: Self.timestamp,
        )

        #expect(objectId.hasPrefix("counter:"))
        #expect(objectId.contains("@1700000000000"))

        let (typePart, hashPart, timestampPart) = try parseObjectId(objectId)
        #expect(typePart == "counter")
        #expect(timestampPart == "1700000000000")
        // RTO14b2: base64url — no standard-base64 characters.
        #expect(!hashPart.isEmpty)
        #expect(!hashPart.contains("+"))
        #expect(!hashPart.contains("/"))
        #expect(!hashPart.contains("="))
    }

    // UTS: objects/unit/RTO14/objectid-format-map-0
    @Test
    func test_RTO14_objectId_format_for_map_type() {
        let objectId = ObjectCreationHelpers.testsOnly_createObjectID(
            type: "map",
            initialValue: #"{"map":{"semantics":"LWW","entries":{}}}"#,
            nonce: "test-nonce-12345678",
            timestamp: Self.timestamp,
        )

        #expect(objectId.hasPrefix("map:"))
        #expect(objectId.contains("@1700000000000"))
    }
    
    // UTS: objects/unit/RTO14/deterministic-0
    @Test
    func test_RTO14_deterministic_output_for_same_inputs() {
        let make = {
            ObjectCreationHelpers.testsOnly_createObjectID(
                type: "counter",
                initialValue: #"{"counter":{"count":0}}"#,
                nonce: "same-nonce-1234567",
                timestamp: Self.timestamp,
            )
        }
        #expect(make() == make())
    }

    // UTS: objects/unit/RTO14/different-nonce-0
    @Test
    func test_RTO14_different_nonce_produces_different_objectId() {
        let id1 = ObjectCreationHelpers.testsOnly_createObjectID(
            type: "counter", initialValue: #"{"counter":{"count":0}}"#, nonce: "nonce-aaaaaaaaaaaaa", timestamp: Self.timestamp,
        )
        let id2 = ObjectCreationHelpers.testsOnly_createObjectID(
            type: "counter", initialValue: #"{"counter":{"count":0}}"#, nonce: "nonce-bbbbbbbbbbbbb", timestamp: Self.timestamp,
        )
        #expect(id1 != id2)
    }

    // UTS: objects/unit/RTO14b/base64url-encoding-0
    @Test
    func test_RTO14b_hash_is_base64url_encoded_not_standard_base64() throws {
        let objectId = ObjectCreationHelpers.testsOnly_createObjectID(
            type: "counter", initialValue: #"{"counter":{"count":0}}"#, nonce: "test-nonce-12345678", timestamp: Self.timestamp,
        )
        let (_, hashPart, _) = try parseObjectId(objectId)
        #expect(!hashPart.contains("+"))
        #expect(!hashPart.contains("/"))
        #expect(!hashPart.hasSuffix("="))
    }
}

private extension ObjectIdTests {
    /// Splits an objectId `{type}:{hash}@{timestamp}` into its parts.
    private func parseObjectId(_ objectId: String) throws -> (type: String, hash: String, timestamp: String) {
        let typeSplit = objectId.split(separator: ":", maxSplits: 1)
        let typePart = try #require(typeSplit.first.map(String.init))
        let rest = try #require(typeSplit.count > 1 ? String(typeSplit[1]) : nil)
        let hashAndTimestamp = rest.split(separator: "@", maxSplits: 1)
        let hashPart = try #require(hashAndTimestamp.first.map(String.init))
        let timestampPart = try #require(hashAndTimestamp.count > 1 ? String(hashAndTimestamp[1]) : nil)
        return (typePart, hashPart, timestampPart)
    }
}
