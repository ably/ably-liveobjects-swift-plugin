import Ably
import Foundation
@testable import AblyLiveObjects

/// Payload extraction for ``Instance`` — the Swift equivalent of the spec's loosely-typed `Instance`
/// casts. Non-optional: use ``Instance/type`` to discriminate the case first (these trap on a
/// mismatch, like a forced cast).
extension Instance {
    /// The `objectId` of the wrapped live object (RTINS3), or `nil` for a primitive.
    func id() -> String? {
        switch self {
        case let .liveMap(map):
            map.id
        case let .liveCounter(counter):
            counter.id
        case .primitive:
            nil
        }
    }

    func asLiveMap() -> any LiveMapInstance {
        guard case let .liveMap(map) = self else { preconditionFailure("Instance is not a LiveMap") }
        return map
    }

    func asLiveCounter() -> any LiveCounterInstance {
        guard case let .liveCounter(counter) = self else { preconditionFailure("Instance is not a LiveCounter") }
        return counter
    }

    func asPrimitive() -> any PrimitiveInstance {
        guard case let .primitive(primitive) = self else { preconditionFailure("Instance is not a Primitive") }
        return primitive
    }
}

/// Typed shortcuts through ``PrimitiveInstance/value`` so tests can write
/// `asPrimitive().stringValue` instead of `asPrimitive().value.stringValue`.
extension PrimitiveInstance {
    var stringValue: String? { get throws(ARTErrorInfo) { try value.stringValue } }
    var numberValue: Double? { get throws(ARTErrorInfo) { try value.numberValue } }
    var boolValue: Bool? { get throws(ARTErrorInfo) { try value.boolValue } }
    var dataValue: Data? { get throws(ARTErrorInfo) { try value.dataValue } }
    var jsonArrayValue: [JSONValue]? { get throws(ARTErrorInfo) { try value.jsonArrayValue } }
    var jsonObjectValue: [String: JSONValue]? { get throws(ARTErrorInfo) { try value.jsonObjectValue } }
}

/// Typed shortcuts through ``PrimitivePathObject/value()`` so tests can write
/// `asPrimitive().stringValue` instead of `asPrimitive().value()?.stringValue`.
extension PrimitivePathObject {
    var stringValue: String? { get throws(ARTErrorInfo) { try value()?.stringValue } }
    var numberValue: Double? { get throws(ARTErrorInfo) { try value()?.numberValue } }
    var boolValue: Bool? { get throws(ARTErrorInfo) { try value()?.boolValue } }
    var dataValue: Data? { get throws(ARTErrorInfo) { try value()?.dataValue } }
    var jsonArrayValue: [JSONValue]? { get throws(ARTErrorInfo) { try value()?.jsonArrayValue } }
    var jsonObjectValue: [String: JSONValue]? { get throws(ARTErrorInfo) { try value()?.jsonObjectValue } }
}
