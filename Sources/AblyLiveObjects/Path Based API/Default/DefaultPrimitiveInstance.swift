import Ably

internal final class DefaultPrimitiveInstance: PrimitiveInstance {
    internal var value: Primitive {
        get throws(ARTErrorInfo) {
            notImplemented()
        }
    }

    internal var type: ValueType {
        notImplemented()
    }

    internal func compactJson() throws(ARTErrorInfo) -> JSONValue {
        notImplemented()
    }
}
