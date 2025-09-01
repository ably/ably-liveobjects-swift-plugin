@testable import AblyLiveObjects
import Foundation

/// A mock delegate that can return predefined objects
final class MockLiveMapObjectPoolDelegate: LiveMapObjectPoolDelegate {
    private let objectsMutex: DispatchQueueMutex<[String: ObjectsPool.Entry]>

    init(internalQueue: DispatchQueue) {
        objectsMutex = DispatchQueueMutex(dispatchQueue: internalQueue, initialValue: [:])
    }

    var objects: [String: ObjectsPool.Entry] {
        get {
            objectsMutex.withLock { $0 }
        }
        set {
            objectsMutex.withLock { $0 = newValue }
        }
    }

    func nosync_getObjectFromPool(id: String) -> ObjectsPool.Entry? {
        objectsMutex.withoutLock { $0[id] }
    }
}
