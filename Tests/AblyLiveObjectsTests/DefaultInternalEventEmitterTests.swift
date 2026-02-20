@testable import AblyLiveObjects
import Foundation
import Testing

struct DefaultInternalEventEmitterTests {
    // Test event types for testing
    enum TestEvent: String, Equatable, CaseIterable, Sendable {
        case connect
        case disconnect
        case message
    }

    struct TestData: Equatable, Sendable {
        let value: String
    }

    /// Mutable reference wrapper that is `@unchecked Sendable`.
    ///
    /// Safe in these tests because all access occurs on the same serial queue.
    private final class Ref<T>: @unchecked Sendable {
        var value: T
        init(_ value: T) { self.value = value }
    }

    // MARK: - RTE3 Tests (on method)

    @Test
    func onListenerForAllEvents() {
        let internalQueue = TestFactories.createInternalQueue()
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
        let receivedEvents = Ref<[(TestEvent, TestData)]>([])

        internalQueue.ably_syncNoDeadlock {
            // RTE3: Register listener for all events
            emitter.nosync_on { event, data in
                receivedEvents.value.append((event, data))
            }

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)
            emitter.nosync_emit(event: .disconnect, data: testData)

            #expect(receivedEvents.value.count == 2)
            #expect(receivedEvents.value[0].0 == .connect)
            #expect(receivedEvents.value[1].0 == .disconnect)
        }
    }

    @Test
    func onListenerForSpecificEvent() {
        let internalQueue = TestFactories.createInternalQueue()
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
        let receivedData = Ref<[TestData]>([])

        internalQueue.ably_syncNoDeadlock {
            // RTE3: Register listener for specific event
            emitter.nosync_on(.connect) { data in
                receivedData.value.append(data)
            }

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)
            emitter.nosync_emit(event: .disconnect, data: testData) // Should not trigger listener

            #expect(receivedData.value.count == 1)
            #expect(receivedData.value[0].value == "test")
        }
    }

    @Test
    func onListenerWithSignal() {
        let internalQueue = TestFactories.createInternalQueue()
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
        let controller = SubscriptionController(internalQueue: internalQueue)
        let receivedEvents = Ref<[(TestEvent, TestData)]>([])

        internalQueue.ably_syncNoDeadlock {
            // RTE3: Register listener with signal
            emitter.nosync_on(signalledBy: controller.signal) { event, data in
                receivedEvents.value.append((event, data))
            }

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)

            // RTE5: Cancel subscription
            controller.nosync_off()

            emitter.nosync_emit(event: .disconnect, data: testData) // Should not trigger

            #expect(receivedEvents.value.count == 1)
            #expect(receivedEvents.value[0].0 == .connect)
        }
    }

    @Test
    func onListenerMultipleRegistrations() {
        let internalQueue = TestFactories.createInternalQueue()
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
        let callCount = Ref(0)

        internalQueue.ably_syncNoDeadlock {
            let listener: EventListener<TestEvent, TestData> = { _, _ in
                callCount.value += 1
            }

            // RTE3: If on is called more than once with same listener, it's added multiple times
            emitter.nosync_on(listener)
            emitter.nosync_on(listener)

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)

            #expect(callCount.value == 2) // Listener should be called twice
        }
    }

    @Test
    func onListenerForSpecificEventWithSignal() {
        let internalQueue = TestFactories.createInternalQueue()
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
        let controller = SubscriptionController(internalQueue: internalQueue)
        let receivedData = Ref<[TestData]>([])

        internalQueue.ably_syncNoDeadlock {
            // RTE3: Register listener for specific event with signal
            emitter.nosync_on(.connect, signalledBy: controller.signal) { data in
                receivedData.value.append(data)
            }

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)
            emitter.nosync_emit(event: .disconnect, data: testData) // Should not trigger listener

            #expect(receivedData.value.count == 1)
            #expect(receivedData.value[0].value == "test")

            // RTE5: Cancel subscription
            controller.nosync_off()

            emitter.nosync_emit(event: .connect, data: testData) // Should not trigger after nosync_off()
            #expect(receivedData.value.count == 1) // Should not increment
        }
    }

    // MARK: - RTE4 Tests (once method)

    @Test
    func onceListenerForAllEvents() {
        let internalQueue = TestFactories.createInternalQueue()
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
        let receivedEvents = Ref<[(TestEvent, TestData)]>([])

        internalQueue.ably_syncNoDeadlock {
            // RTE4: Register one-time listener
            emitter.nosync_once { event, data in
                receivedEvents.value.append((event, data))
            }

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)
            emitter.nosync_emit(event: .disconnect, data: testData) // Should not trigger

            #expect(receivedEvents.value.count == 1)
            #expect(receivedEvents.value[0].0 == .connect)
        }
    }

    @Test
    func onceListenerForSpecificEvent() {
        let internalQueue = TestFactories.createInternalQueue()
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
        let receivedData = Ref<[TestData]>([])

        internalQueue.ably_syncNoDeadlock {
            // RTE4: Register one-time listener for specific event
            emitter.nosync_once(.connect) { data in
                receivedData.value.append(data)
            }

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)
            emitter.nosync_emit(event: .connect, data: testData) // Should not trigger again

            #expect(receivedData.value.count == 1)
            #expect(receivedData.value[0].value == "test")
        }
    }

    @Test
    func onceListenerMultipleRegistrations() {
        let internalQueue = TestFactories.createInternalQueue()
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
        let callCount = Ref(0)

        internalQueue.ably_syncNoDeadlock {
            let listener: EventListener<TestEvent, TestData> = { _, _ in
                callCount.value += 1
            }

            // RTE4: If once is called multiple times with same listener, each registration is invoked once
            emitter.nosync_once(listener)
            emitter.nosync_once(listener)

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)

            #expect(callCount.value == 2) // Both registrations should be called once

            emitter.nosync_emit(event: .disconnect, data: testData) // Should not trigger any more
            #expect(callCount.value == 2) // Count should remain the same
        }
    }

    @Test
    func onceListenerWithSignal() {
        let internalQueue = TestFactories.createInternalQueue()
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
        let controller = SubscriptionController(internalQueue: internalQueue)
        let receivedEvents = Ref<[(TestEvent, TestData)]>([])

        internalQueue.ably_syncNoDeadlock {
            // RTE4: Register one-time listener with signal
            emitter.nosync_once(signalledBy: controller.signal) { event, data in
                receivedEvents.value.append((event, data))
            }

            // RTE5: Cancel subscription before it fires
            controller.nosync_off()

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData) // Should not trigger due to nosync_off()

            #expect(receivedEvents.value.isEmpty)
        }
    }

    @Test
    func onceListenerForSpecificEventWithSignal() {
        let internalQueue = TestFactories.createInternalQueue()
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
        let controller = SubscriptionController(internalQueue: internalQueue)
        let receivedData = Ref<[TestData]>([])

        internalQueue.ably_syncNoDeadlock {
            // RTE4: Register one-time listener for specific event with signal
            emitter.nosync_once(.connect, signalledBy: controller.signal) { data in
                receivedData.value.append(data)
            }

            // RTE5: Cancel subscription before it fires
            controller.nosync_off()

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData) // Should not trigger due to nosync_off()

            #expect(receivedData.value.isEmpty)
        }
    }

    // MARK: - RTE6 Tests (emit method)

    @Test
    func emitCallsAllRegisteredListeners() {
        let internalQueue = TestFactories.createInternalQueue()
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
        let allEventCallCount = Ref(0)
        let namedEventCallCount = Ref(0)

        internalQueue.ably_syncNoDeadlock {
            emitter.nosync_on { _, _ in allEventCallCount.value += 1 }
            emitter.nosync_on(.connect) { _ in namedEventCallCount.value += 1 }

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)

            #expect(allEventCallCount.value == 1)
            #expect(namedEventCallCount.value == 1)
        }
    }

    // MARK: - RTE6a Tests (listener set stability during emit)

    @Test
    func emitListenerSetStability() {
        let internalQueue = TestFactories.createInternalQueue()
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
        let callOrder = Ref<[String]>([])

        internalQueue.ably_syncNoDeadlock {
            emitter.nosync_on { _, _ in
                callOrder.value.append("first")
                // Add another listener during emit - should not be called in this emit
                emitter.nosync_on { _, _ in
                    callOrder.value.append("added-during-emit")
                }
            }

            emitter.nosync_on { _, _ in
                callOrder.value.append("second")
            }

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)

            // RTE6a: Only original listeners should be called
            #expect(callOrder.value == ["first", "second"])

            // Emit again - now the added listener should be called
            callOrder.value.removeAll()
            emitter.nosync_emit(event: .disconnect, data: testData)

            #expect(callOrder.value == ["first", "second", "added-during-emit"])
        }
    }

    @Test
    func emitListenerRemovalDuringEmit() {
        let internalQueue = TestFactories.createInternalQueue()
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
        let controller = SubscriptionController(internalQueue: internalQueue)
        let callOrder = Ref<[String]>([])

        internalQueue.ably_syncNoDeadlock {
            emitter.nosync_on { _, _ in
                callOrder.value.append("first")
                // Remove this listener during emit - but it should still complete per RTE6a
                controller.nosync_off()
            }

            emitter.nosync_on(signalledBy: controller.signal) { _, _ in
                callOrder.value.append("second")
            }

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)

            // RTE6a: Both listeners should be called despite removal during emit
            #expect(callOrder.value == ["first", "second"])

            // Emit again - now only first listener should be called
            callOrder.value.removeAll()
            emitter.nosync_emit(event: .disconnect, data: testData)

            #expect(callOrder.value == ["first"])
        }
    }

    // MARK: - RTE5 Tests (off method)

    @Test
    func offRemovesAllListeners() {
        let internalQueue = TestFactories.createInternalQueue()
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
        let allEventCallCount = Ref(0)
        let connectCallCount = Ref(0)
        let disconnectCallCount = Ref(0)

        internalQueue.ably_syncNoDeadlock {
            // Register various listeners
            emitter.nosync_on { _, _ in allEventCallCount.value += 1 }
            emitter.nosync_on(.connect) { _ in connectCallCount.value += 1 }
            emitter.nosync_on(.disconnect) { _ in disconnectCallCount.value += 1 }

            let testData = TestData(value: "test")

            // Verify listeners work before nosync_off()
            emitter.nosync_emit(event: .connect, data: testData)
            #expect(allEventCallCount.value == 1)
            #expect(connectCallCount.value == 1)
            #expect(disconnectCallCount.value == 0)

            // RTE5: Remove all listeners
            emitter.nosync_off()

            // Emit again - no listeners should be called
            allEventCallCount.value = 0
            connectCallCount.value = 0
            disconnectCallCount.value = 0

            emitter.nosync_emit(event: .connect, data: testData)
            emitter.nosync_emit(event: .disconnect, data: testData)

            #expect(allEventCallCount.value == 0)
            #expect(connectCallCount.value == 0)
            #expect(disconnectCallCount.value == 0)
        }
    }

    @Test
    func offForSpecificEventRemovesOnlyThatEvent() {
        let internalQueue = TestFactories.createInternalQueue()
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
        let allEventCallCount = Ref(0)
        let connectCallCount = Ref(0)
        let disconnectCallCount = Ref(0)

        internalQueue.ably_syncNoDeadlock {
            // Register various listeners
            emitter.nosync_on { _, _ in allEventCallCount.value += 1 }
            emitter.nosync_on(.connect) { _ in connectCallCount.value += 1 }
            emitter.nosync_on(.disconnect) { _ in disconnectCallCount.value += 1 }

            let testData = TestData(value: "test")

            // Verify listeners work before nosync_off()
            emitter.nosync_emit(event: .connect, data: testData)
            #expect(allEventCallCount.value == 1)
            #expect(connectCallCount.value == 1)
            #expect(disconnectCallCount.value == 0)

            // RTE5: Remove only connect listeners
            emitter.nosync_off(.connect)

            // Reset counters and emit - only connect listeners should be removed
            allEventCallCount.value = 0
            connectCallCount.value = 0
            disconnectCallCount.value = 0

            emitter.nosync_emit(event: .connect, data: testData)
            #expect(allEventCallCount.value == 1) // All-event listener should still work
            #expect(connectCallCount.value == 0) // Connect listener should be removed
            #expect(disconnectCallCount.value == 0)

            emitter.nosync_emit(event: .disconnect, data: testData)
            #expect(allEventCallCount.value == 2) // All-event listener should still work
            #expect(connectCallCount.value == 0)
            #expect(disconnectCallCount.value == 1) // Disconnect listener should still work
        }
    }

    // MARK: - RTE5 - SubscriptionController Tests

    @Test
    func subscriptionControllerOff() {
        let internalQueue = TestFactories.createInternalQueue()
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
        let controller = SubscriptionController(internalQueue: internalQueue)
        let callCount = Ref(0)

        internalQueue.ably_syncNoDeadlock {
            emitter.nosync_on(signalledBy: controller.signal) { _, _ in
                callCount.value += 1
            }

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)
            #expect(callCount.value == 1)

            controller.nosync_off()
            emitter.nosync_emit(event: .disconnect, data: testData)
            #expect(callCount.value == 1) // Should not increment
        }
    }

    @Test
    func unsubscribeFromWithinListener() {
        let internalQueue = TestFactories.createInternalQueue()
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
        let controller = SubscriptionController(internalQueue: internalQueue)
        let callCount = Ref(0)

        internalQueue.ably_syncNoDeadlock {
            // Test unsubscribing from within listener callback
            emitter.nosync_on(signalledBy: controller.signal) { _, _ in
                callCount.value += 1
                controller.nosync_off() // Unsubscribe from within callback
            }

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)
            #expect(callCount.value == 1)

            // Should not be called again
            emitter.nosync_emit(event: .disconnect, data: testData)
            #expect(callCount.value == 1)
        }
    }

    @Test
    func subscriptionControllerOffDoesNotAffectFutureSubscriptions() {
        let internalQueue = TestFactories.createInternalQueue()
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
        let controller = SubscriptionController(internalQueue: internalQueue)
        let firstCallCount = Ref(0)
        let secondCallCount = Ref(0)

        internalQueue.ably_syncNoDeadlock {
            // First subscription
            emitter.nosync_on(signalledBy: controller.signal) { _, _ in
                firstCallCount.value += 1
            }

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)
            #expect(firstCallCount.value == 1)

            // Cancel first subscription
            controller.nosync_off()

            // Add another subscription with the same signal - should work
            emitter.nosync_on(signalledBy: controller.signal) { _, _ in
                secondCallCount.value += 1
            }

            emitter.nosync_emit(event: .disconnect, data: testData)
            #expect(firstCallCount.value == 1) // Should not increment
            #expect(secondCallCount.value == 1) // Should work despite previous nosync_off() call
        }
    }

    @Test
    func subscriptionContinuesAfterControllerDeallocation() {
        let internalQueue = TestFactories.createInternalQueue()
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
        let callCount = Ref(0)

        // Create subscription with controller that will be deallocated
        weak var weakController: SubscriptionController?
        internalQueue.ably_syncNoDeadlock {
            let controller = SubscriptionController(internalQueue: internalQueue)
            weakController = controller
            emitter.nosync_on(signalledBy: controller.signal) { _, _ in
                callCount.value += 1
            }

            // Verify subscription works initially
            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)
            #expect(callCount.value == 1)

            // Controller will be deallocated when leaving this scope
        }
        // Confirm the controller has been deallocated
        precondition(weakController == nil)

        // Emit another value now that the controller has been deallocated
        internalQueue.ably_syncNoDeadlock {
            let testData = TestData(value: "test2")
            emitter.nosync_emit(event: .disconnect, data: testData)

            // The subscription should still work because listener registration is independent
            // of controller lifetime - only calling nosync_off() should remove it
            #expect(callCount.value == 2)
        }
    }

    // MARK: - Mixed Scenarios Tests

    @Test
    func mixedOnAndOnceListeners() {
        let internalQueue = TestFactories.createInternalQueue()
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
        let onCallCount = Ref(0)
        let onceCallCount = Ref(0)

        internalQueue.ably_syncNoDeadlock {
            emitter.nosync_on { _, _ in onCallCount.value += 1 }
            emitter.nosync_once { _, _ in onceCallCount.value += 1 }

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)
            #expect(onCallCount.value == 1)
            #expect(onceCallCount.value == 1)

            emitter.nosync_emit(event: .disconnect, data: testData)
            #expect(onCallCount.value == 2) // Should increment
            #expect(onceCallCount.value == 1) // Should not increment
        }
    }

    @Test
    func mixedAllEventAndNamedEventListeners() {
        let internalQueue = TestFactories.createInternalQueue()
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
        let allEventCallCount = Ref(0)
        let connectCallCount = Ref(0)
        let disconnectCallCount = Ref(0)

        internalQueue.ably_syncNoDeadlock {
            emitter.nosync_on { _, _ in allEventCallCount.value += 1 }
            emitter.nosync_on(.connect) { _ in connectCallCount.value += 1 }
            emitter.nosync_on(.disconnect) { _ in disconnectCallCount.value += 1 }

            let testData = TestData(value: "test")

            emitter.nosync_emit(event: .connect, data: testData)
            #expect(allEventCallCount.value == 1)
            #expect(connectCallCount.value == 1)
            #expect(disconnectCallCount.value == 0)

            emitter.nosync_emit(event: .disconnect, data: testData)
            #expect(allEventCallCount.value == 2)
            #expect(connectCallCount.value == 1)
            #expect(disconnectCallCount.value == 1)

            emitter.nosync_emit(event: .message, data: testData)
            #expect(allEventCallCount.value == 3)
            #expect(connectCallCount.value == 1)
            #expect(disconnectCallCount.value == 1)
        }
    }

    @Test
    func complexScenario() {
        let internalQueue = TestFactories.createInternalQueue()
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
        let controller1 = SubscriptionController(internalQueue: internalQueue)
        let controller2 = SubscriptionController(internalQueue: internalQueue)
        let results = Ref<[String]>([])

        internalQueue.ably_syncNoDeadlock {
            // Mix of on/once, all-event/named-event, with/without signals
            emitter.nosync_on { event, _ in results.value.append("all-on-\(event)") }
            emitter.nosync_once { event, _ in results.value.append("all-once-\(event)") }
            emitter.nosync_on(.connect) { _ in results.value.append("connect-on") }
            emitter.nosync_once(.connect) { _ in results.value.append("connect-once") }
            emitter.nosync_on(signalledBy: controller1.signal) { event, _ in results.value.append("signal1-\(event)") }
            emitter.nosync_on(.connect, signalledBy: controller2.signal) { _ in results.value.append("connect-signal2") }

            let testData = TestData(value: "test")

            // First emit
            emitter.nosync_emit(event: .connect, data: testData)
            #expect(results.value.count == 6)
            #expect(results.value.contains("all-on-connect"))
            #expect(results.value.contains("all-once-connect"))
            #expect(results.value.contains("connect-on"))
            #expect(results.value.contains("connect-once"))
            #expect(results.value.contains("signal1-connect"))
            #expect(results.value.contains("connect-signal2"))

            results.value.removeAll()

            // Cancel one signal
            controller1.nosync_off()

            // Second emit
            emitter.nosync_emit(event: .connect, data: testData)
            #expect(results.value.count == 3) // once listeners should not fire again, signal1 should not fire
            #expect(results.value.contains("all-on-connect"))
            #expect(results.value.contains("connect-on"))
            #expect(results.value.contains("connect-signal2"))
            #expect(!results.value.contains("all-once-connect"))
            #expect(!results.value.contains("connect-once"))
            #expect(!results.value.contains("signal1-connect"))
        }
    }
}
