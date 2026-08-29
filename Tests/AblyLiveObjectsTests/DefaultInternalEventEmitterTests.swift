// NOTE: This file is adapted from the WIP ably-swift (taken from there at commit 98996f1).

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

    // MARK: - RTE3 Tests (on method)

    @Test
    func onListenerForAllEvents() {
        let internalQueue = TestFactories.createInternalQueue()

        internalQueue.ably_syncNoDeadlock {
            let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
            let receivedEvents = DispatchQueueMutex<[(TestEvent, TestData)]>(dispatchQueue: internalQueue, initialValue: [])

            // RTE3: Register listener for all events
            emitter.nosync_on { event, data in
                receivedEvents.withoutSync { $0.append((event, data)) }
            }

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)
            emitter.nosync_emit(event: .disconnect, data: testData)

            let received = receivedEvents.withoutSync { $0 }
            #expect(received.count == 2)
            #expect(received[0].0 == .connect)
            #expect(received[1].0 == .disconnect)
        }
    }

    @Test
    func onListenerForSpecificEvent() {
        let internalQueue = TestFactories.createInternalQueue()

        internalQueue.ably_syncNoDeadlock {
            let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
            let receivedData = DispatchQueueMutex<[TestData]>(dispatchQueue: internalQueue, initialValue: [])

            // RTE3: Register listener for specific event
            emitter.nosync_on(.connect) { data in
                receivedData.withoutSync { $0.append(data) }
            }

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)
            emitter.nosync_emit(event: .disconnect, data: testData) // Should not trigger listener

            let received = receivedData.withoutSync { $0 }
            #expect(received.count == 1)
            #expect(received[0].value == "test")
        }
    }

    @Test
    func onListenerWithSignal() {
        let internalQueue = TestFactories.createInternalQueue()

        internalQueue.ably_syncNoDeadlock {
            let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
            let controller = SubscriptionController(internalQueue: internalQueue)
            let receivedEvents = DispatchQueueMutex<[(TestEvent, TestData)]>(dispatchQueue: internalQueue, initialValue: [])

            // RTE3: Register listener with signal
            emitter.nosync_on(signalledBy: controller.signal) { event, data in
                receivedEvents.withoutSync { $0.append((event, data)) }
            }

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)

            // RTE5: Cancel subscription
            controller.nosync_off()

            emitter.nosync_emit(event: .disconnect, data: testData) // Should not trigger

            let received = receivedEvents.withoutSync { $0 }
            #expect(received.count == 1)
            #expect(received[0].0 == .connect)
        }
    }

    @Test
    func onListenerMultipleRegistrations() {
        let internalQueue = TestFactories.createInternalQueue()

        internalQueue.ably_syncNoDeadlock {
            let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
            let callCount = DispatchQueueMutex(dispatchQueue: internalQueue, initialValue: 0)

            let listener: EventListener<TestEvent, TestData> = { _, _ in
                callCount.withoutSync { $0 += 1 }
            }

            // RTE3: If on is called more than once with same listener, it's added multiple times
            emitter.nosync_on(listener)
            emitter.nosync_on(listener)

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)

            #expect(callCount.withoutSync { $0 } == 2) // Listener should be called twice
        }
    }

    @Test
    func onListenerForSpecificEventWithSignal() {
        let internalQueue = TestFactories.createInternalQueue()

        internalQueue.ably_syncNoDeadlock {
            let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
            let controller = SubscriptionController(internalQueue: internalQueue)
            let receivedData = DispatchQueueMutex<[TestData]>(dispatchQueue: internalQueue, initialValue: [])

            // RTE3: Register listener for specific event with signal
            emitter.nosync_on(.connect, signalledBy: controller.signal) { data in
                receivedData.withoutSync { $0.append(data) }
            }

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)
            emitter.nosync_emit(event: .disconnect, data: testData) // Should not trigger listener

            let received = receivedData.withoutSync { $0 }
            #expect(received.count == 1)
            #expect(received[0].value == "test")

            // RTE5: Cancel subscription
            controller.nosync_off()

            emitter.nosync_emit(event: .connect, data: testData) // Should not trigger after nosync_off()
            #expect(receivedData.withoutSync { $0.count } == 1) // Should not increment
        }
    }

    // MARK: - RTE4 Tests (once method)

    @Test
    func onceListenerForAllEvents() {
        let internalQueue = TestFactories.createInternalQueue()

        internalQueue.ably_syncNoDeadlock {
            let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
            let receivedEvents = DispatchQueueMutex<[(TestEvent, TestData)]>(dispatchQueue: internalQueue, initialValue: [])

            // RTE4: Register one-time listener
            emitter.nosync_once { event, data in
                receivedEvents.withoutSync { $0.append((event, data)) }
            }

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)
            emitter.nosync_emit(event: .disconnect, data: testData) // Should not trigger

            let received = receivedEvents.withoutSync { $0 }
            #expect(received.count == 1)
            #expect(received[0].0 == .connect)
        }
    }

    @Test
    func onceListenerForSpecificEvent() {
        let internalQueue = TestFactories.createInternalQueue()

        internalQueue.ably_syncNoDeadlock {
            let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
            let receivedData = DispatchQueueMutex<[TestData]>(dispatchQueue: internalQueue, initialValue: [])

            // RTE4: Register one-time listener for specific event
            emitter.nosync_once(.connect) { data in
                receivedData.withoutSync { $0.append(data) }
            }

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)
            emitter.nosync_emit(event: .connect, data: testData) // Should not trigger again

            let received = receivedData.withoutSync { $0 }
            #expect(received.count == 1)
            #expect(received[0].value == "test")
        }
    }

    @Test
    func onceListenerMultipleRegistrations() {
        let internalQueue = TestFactories.createInternalQueue()

        internalQueue.ably_syncNoDeadlock {
            let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
            let callCount = DispatchQueueMutex(dispatchQueue: internalQueue, initialValue: 0)

            let listener: EventListener<TestEvent, TestData> = { _, _ in
                callCount.withoutSync { $0 += 1 }
            }

            // RTE4: If once is called multiple times with same listener, each registration is invoked once
            emitter.nosync_once(listener)
            emitter.nosync_once(listener)

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)

            #expect(callCount.withoutSync { $0 } == 2) // Both registrations should be called once

            emitter.nosync_emit(event: .disconnect, data: testData) // Should not trigger any more
            #expect(callCount.withoutSync { $0 } == 2) // Count should remain the same
        }
    }

    @Test
    func onceListenerWithSignal() {
        let internalQueue = TestFactories.createInternalQueue()

        internalQueue.ably_syncNoDeadlock {
            let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
            let controller = SubscriptionController(internalQueue: internalQueue)
            let receivedEvents = DispatchQueueMutex<[(TestEvent, TestData)]>(dispatchQueue: internalQueue, initialValue: [])

            // RTE4: Register one-time listener with signal
            emitter.nosync_once(signalledBy: controller.signal) { event, data in
                receivedEvents.withoutSync { $0.append((event, data)) }
            }

            // RTE5: Cancel subscription before it fires
            controller.nosync_off()

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData) // Should not trigger due to nosync_off()

            #expect(receivedEvents.withoutSync { $0 }.isEmpty)
        }
    }

    @Test
    func onceListenerForSpecificEventWithSignal() {
        let internalQueue = TestFactories.createInternalQueue()

        internalQueue.ably_syncNoDeadlock {
            let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
            let controller = SubscriptionController(internalQueue: internalQueue)
            let receivedData = DispatchQueueMutex<[TestData]>(dispatchQueue: internalQueue, initialValue: [])

            // RTE4: Register one-time listener for specific event with signal
            emitter.nosync_once(.connect, signalledBy: controller.signal) { data in
                receivedData.withoutSync { $0.append(data) }
            }

            // RTE5: Cancel subscription before it fires
            controller.nosync_off()

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData) // Should not trigger due to nosync_off()

            #expect(receivedData.withoutSync { $0 }.isEmpty)
        }
    }

    // MARK: - RTE6 Tests (emit method)

    @Test
    func emitCallsAllRegisteredListeners() {
        let internalQueue = TestFactories.createInternalQueue()

        internalQueue.ably_syncNoDeadlock {
            let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
            let allEventCallCount = DispatchQueueMutex(dispatchQueue: internalQueue, initialValue: 0)
            let namedEventCallCount = DispatchQueueMutex(dispatchQueue: internalQueue, initialValue: 0)

            emitter.nosync_on { _, _ in allEventCallCount.withoutSync { $0 += 1 } }
            emitter.nosync_on(.connect) { _ in namedEventCallCount.withoutSync { $0 += 1 } }

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)

            #expect(allEventCallCount.withoutSync { $0 } == 1)
            #expect(namedEventCallCount.withoutSync { $0 } == 1)
        }
    }

    // MARK: - RTE6a Tests (listener set stability during emit)

    @Test
    func emitListenerSetStability() {
        let internalQueue = TestFactories.createInternalQueue()

        internalQueue.ably_syncNoDeadlock {
            let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
            let callOrder = DispatchQueueMutex<[String]>(dispatchQueue: internalQueue, initialValue: [])

            emitter.nosync_on { _, _ in
                callOrder.withoutSync { $0.append("first") }
                // Add another listener during emit - should not be called in this emit
                emitter.nosync_on { _, _ in
                    callOrder.withoutSync { $0.append("added-during-emit") }
                }
            }

            emitter.nosync_on { _, _ in
                callOrder.withoutSync { $0.append("second") }
            }

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)

            // RTE6a: Only original listeners should be called
            #expect(callOrder.withoutSync { $0 } == ["first", "second"])

            // Emit again - now the added listener should be called
            callOrder.withoutSync { $0.removeAll() }
            emitter.nosync_emit(event: .disconnect, data: testData)

            #expect(callOrder.withoutSync { $0 } == ["first", "second", "added-during-emit"])
        }
    }

    @Test
    func emitListenerRemovalDuringEmit() {
        let internalQueue = TestFactories.createInternalQueue()

        internalQueue.ably_syncNoDeadlock {
            let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
            let controller = SubscriptionController(internalQueue: internalQueue)
            let callOrder = DispatchQueueMutex<[String]>(dispatchQueue: internalQueue, initialValue: [])

            emitter.nosync_on { _, _ in
                callOrder.withoutSync { $0.append("first") }
                // Remove this listener during emit - but it should still complete per RTE6a
                controller.nosync_off()
            }

            emitter.nosync_on(signalledBy: controller.signal) { _, _ in
                callOrder.withoutSync { $0.append("second") }
            }

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)

            // RTE6a: Both listeners should be called despite removal during emit
            #expect(callOrder.withoutSync { $0 } == ["first", "second"])

            // Emit again - now only first listener should be called
            callOrder.withoutSync { $0.removeAll() }
            emitter.nosync_emit(event: .disconnect, data: testData)

            #expect(callOrder.withoutSync { $0 } == ["first"])
        }
    }

    // MARK: - RTE5 Tests (off method)

    @Test
    func offRemovesAllListeners() {
        let internalQueue = TestFactories.createInternalQueue()

        internalQueue.ably_syncNoDeadlock {
            let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
            let allEventCallCount = DispatchQueueMutex(dispatchQueue: internalQueue, initialValue: 0)
            let connectCallCount = DispatchQueueMutex(dispatchQueue: internalQueue, initialValue: 0)
            let disconnectCallCount = DispatchQueueMutex(dispatchQueue: internalQueue, initialValue: 0)

            // Register various listeners
            emitter.nosync_on { _, _ in allEventCallCount.withoutSync { $0 += 1 } }
            emitter.nosync_on(.connect) { _ in connectCallCount.withoutSync { $0 += 1 } }
            emitter.nosync_on(.disconnect) { _ in disconnectCallCount.withoutSync { $0 += 1 } }

            let testData = TestData(value: "test")

            // Verify listeners work before nosync_off()
            emitter.nosync_emit(event: .connect, data: testData)
            #expect(allEventCallCount.withoutSync { $0 } == 1)
            #expect(connectCallCount.withoutSync { $0 } == 1)
            #expect(disconnectCallCount.withoutSync { $0 } == 0)

            // RTE5: Remove all listeners
            emitter.nosync_off()

            // Emit again - no listeners should be called
            allEventCallCount.withoutSync { $0 = 0 }
            connectCallCount.withoutSync { $0 = 0 }
            disconnectCallCount.withoutSync { $0 = 0 }

            emitter.nosync_emit(event: .connect, data: testData)
            emitter.nosync_emit(event: .disconnect, data: testData)

            #expect(allEventCallCount.withoutSync { $0 } == 0)
            #expect(connectCallCount.withoutSync { $0 } == 0)
            #expect(disconnectCallCount.withoutSync { $0 } == 0)
        }
    }

    @Test
    func offForSpecificEventRemovesOnlyThatEvent() {
        let internalQueue = TestFactories.createInternalQueue()

        internalQueue.ably_syncNoDeadlock {
            let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
            let allEventCallCount = DispatchQueueMutex(dispatchQueue: internalQueue, initialValue: 0)
            let connectCallCount = DispatchQueueMutex(dispatchQueue: internalQueue, initialValue: 0)
            let disconnectCallCount = DispatchQueueMutex(dispatchQueue: internalQueue, initialValue: 0)

            // Register various listeners
            emitter.nosync_on { _, _ in allEventCallCount.withoutSync { $0 += 1 } }
            emitter.nosync_on(.connect) { _ in connectCallCount.withoutSync { $0 += 1 } }
            emitter.nosync_on(.disconnect) { _ in disconnectCallCount.withoutSync { $0 += 1 } }

            let testData = TestData(value: "test")

            // Verify listeners work before nosync_off()
            emitter.nosync_emit(event: .connect, data: testData)
            #expect(allEventCallCount.withoutSync { $0 } == 1)
            #expect(connectCallCount.withoutSync { $0 } == 1)
            #expect(disconnectCallCount.withoutSync { $0 } == 0)

            // RTE5: Remove only connect listeners
            emitter.nosync_off(.connect)

            // Reset counters and emit - only connect listeners should be removed
            allEventCallCount.withoutSync { $0 = 0 }
            connectCallCount.withoutSync { $0 = 0 }
            disconnectCallCount.withoutSync { $0 = 0 }

            emitter.nosync_emit(event: .connect, data: testData)
            #expect(allEventCallCount.withoutSync { $0 } == 1) // All-event listener should still work
            #expect(connectCallCount.withoutSync { $0 } == 0) // Connect listener should be removed
            #expect(disconnectCallCount.withoutSync { $0 } == 0)

            emitter.nosync_emit(event: .disconnect, data: testData)
            #expect(allEventCallCount.withoutSync { $0 } == 2) // All-event listener should still work
            #expect(connectCallCount.withoutSync { $0 } == 0)
            #expect(disconnectCallCount.withoutSync { $0 } == 1) // Disconnect listener should still work
        }
    }

    // MARK: - RTE5 - SubscriptionController Tests

    @Test
    func subscriptionControllerOff() {
        let internalQueue = TestFactories.createInternalQueue()

        internalQueue.ably_syncNoDeadlock {
            let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
            let controller = SubscriptionController(internalQueue: internalQueue)
            let callCount = DispatchQueueMutex(dispatchQueue: internalQueue, initialValue: 0)

            emitter.nosync_on(signalledBy: controller.signal) { _, _ in
                callCount.withoutSync { $0 += 1 }
            }

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)
            #expect(callCount.withoutSync { $0 } == 1)

            controller.nosync_off()
            emitter.nosync_emit(event: .disconnect, data: testData)
            #expect(callCount.withoutSync { $0 } == 1) // Should not increment
        }
    }

    @Test
    func unsubscribeFromWithinListener() {
        let internalQueue = TestFactories.createInternalQueue()

        internalQueue.ably_syncNoDeadlock {
            let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
            let controller = SubscriptionController(internalQueue: internalQueue)
            let callCount = DispatchQueueMutex(dispatchQueue: internalQueue, initialValue: 0)

            // Test unsubscribing from within listener callback
            emitter.nosync_on(signalledBy: controller.signal) { _, _ in
                callCount.withoutSync { $0 += 1 }
                controller.nosync_off() // Unsubscribe from within callback
            }

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)
            #expect(callCount.withoutSync { $0 } == 1)

            // Should not be called again
            emitter.nosync_emit(event: .disconnect, data: testData)
            #expect(callCount.withoutSync { $0 } == 1)
        }
    }

    @Test
    func subscriptionControllerOffDoesNotAffectFutureSubscriptions() {
        let internalQueue = TestFactories.createInternalQueue()

        internalQueue.ably_syncNoDeadlock {
            let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
            let controller = SubscriptionController(internalQueue: internalQueue)
            let firstCallCount = DispatchQueueMutex(dispatchQueue: internalQueue, initialValue: 0)
            let secondCallCount = DispatchQueueMutex(dispatchQueue: internalQueue, initialValue: 0)

            // First subscription
            emitter.nosync_on(signalledBy: controller.signal) { _, _ in
                firstCallCount.withoutSync { $0 += 1 }
            }

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)
            #expect(firstCallCount.withoutSync { $0 } == 1)

            // Cancel first subscription
            controller.nosync_off()

            // Add another subscription with the same signal - should work
            emitter.nosync_on(signalledBy: controller.signal) { _, _ in
                secondCallCount.withoutSync { $0 += 1 }
            }

            emitter.nosync_emit(event: .disconnect, data: testData)
            #expect(firstCallCount.withoutSync { $0 } == 1) // Should not increment
            #expect(secondCallCount.withoutSync { $0 } == 1) // Should work despite previous nosync_off() call
        }
    }

    @Test
    func subscriptionContinuesAfterControllerDeallocation() {
        let internalQueue = TestFactories.createInternalQueue()
        // `emitter` and `callCount` outlive the first `ably_syncNoDeadlock` block (they are
        // also used by the second one), so they are created here rather than inside it.
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
        let callCount = DispatchQueueMutex(dispatchQueue: internalQueue, initialValue: 0)

        // Create subscription with controller that will be deallocated
        weak var weakController: SubscriptionController?
        internalQueue.ably_syncNoDeadlock {
            let controller = SubscriptionController(internalQueue: internalQueue)
            weakController = controller
            emitter.nosync_on(signalledBy: controller.signal) { _, _ in
                callCount.withoutSync { $0 += 1 }
            }

            // Verify subscription works initially
            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)
            #expect(callCount.withoutSync { $0 } == 1)

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
            #expect(callCount.withoutSync { $0 } == 2)
        }
    }

    // MARK: - Mixed Scenarios Tests

    @Test
    func mixedOnAndOnceListeners() {
        let internalQueue = TestFactories.createInternalQueue()

        internalQueue.ably_syncNoDeadlock {
            let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
            let onCallCount = DispatchQueueMutex(dispatchQueue: internalQueue, initialValue: 0)
            let onceCallCount = DispatchQueueMutex(dispatchQueue: internalQueue, initialValue: 0)

            emitter.nosync_on { _, _ in onCallCount.withoutSync { $0 += 1 } }
            emitter.nosync_once { _, _ in onceCallCount.withoutSync { $0 += 1 } }

            let testData = TestData(value: "test")
            emitter.nosync_emit(event: .connect, data: testData)
            #expect(onCallCount.withoutSync { $0 } == 1)
            #expect(onceCallCount.withoutSync { $0 } == 1)

            emitter.nosync_emit(event: .disconnect, data: testData)
            #expect(onCallCount.withoutSync { $0 } == 2) // Should increment
            #expect(onceCallCount.withoutSync { $0 } == 1) // Should not increment
        }
    }

    @Test
    func mixedAllEventAndNamedEventListeners() {
        let internalQueue = TestFactories.createInternalQueue()

        internalQueue.ably_syncNoDeadlock {
            let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
            let allEventCallCount = DispatchQueueMutex(dispatchQueue: internalQueue, initialValue: 0)
            let connectCallCount = DispatchQueueMutex(dispatchQueue: internalQueue, initialValue: 0)
            let disconnectCallCount = DispatchQueueMutex(dispatchQueue: internalQueue, initialValue: 0)

            emitter.nosync_on { _, _ in allEventCallCount.withoutSync { $0 += 1 } }
            emitter.nosync_on(.connect) { _ in connectCallCount.withoutSync { $0 += 1 } }
            emitter.nosync_on(.disconnect) { _ in disconnectCallCount.withoutSync { $0 += 1 } }

            let testData = TestData(value: "test")

            emitter.nosync_emit(event: .connect, data: testData)
            #expect(allEventCallCount.withoutSync { $0 } == 1)
            #expect(connectCallCount.withoutSync { $0 } == 1)
            #expect(disconnectCallCount.withoutSync { $0 } == 0)

            emitter.nosync_emit(event: .disconnect, data: testData)
            #expect(allEventCallCount.withoutSync { $0 } == 2)
            #expect(connectCallCount.withoutSync { $0 } == 1)
            #expect(disconnectCallCount.withoutSync { $0 } == 1)

            emitter.nosync_emit(event: .message, data: testData)
            #expect(allEventCallCount.withoutSync { $0 } == 3)
            #expect(connectCallCount.withoutSync { $0 } == 1)
            #expect(disconnectCallCount.withoutSync { $0 } == 1)
        }
    }

    @Test
    func complexScenario() {
        let internalQueue = TestFactories.createInternalQueue()

        internalQueue.ably_syncNoDeadlock {
            let emitter = DefaultInternalEventEmitter<TestEvent, TestData>(internalQueue: internalQueue)
            let controller1 = SubscriptionController(internalQueue: internalQueue)
            let controller2 = SubscriptionController(internalQueue: internalQueue)
            let results = DispatchQueueMutex<[String]>(dispatchQueue: internalQueue, initialValue: [])

            // Mix of on/once, all-event/named-event, with/without signals
            emitter.nosync_on { event, _ in results.withoutSync { $0.append("all-on-\(event)") } }
            emitter.nosync_once { event, _ in results.withoutSync { $0.append("all-once-\(event)") } }
            emitter.nosync_on(.connect) { _ in results.withoutSync { $0.append("connect-on") } }
            emitter.nosync_once(.connect) { _ in results.withoutSync { $0.append("connect-once") } }
            emitter.nosync_on(signalledBy: controller1.signal) { event, _ in results.withoutSync { $0.append("signal1-\(event)") } }
            emitter.nosync_on(.connect, signalledBy: controller2.signal) { _ in results.withoutSync { $0.append("connect-signal2") } }

            let testData = TestData(value: "test")

            // First emit
            emitter.nosync_emit(event: .connect, data: testData)
            let firstResults = results.withoutSync { $0 }
            #expect(firstResults.count == 6)
            #expect(firstResults.contains("all-on-connect"))
            #expect(firstResults.contains("all-once-connect"))
            #expect(firstResults.contains("connect-on"))
            #expect(firstResults.contains("connect-once"))
            #expect(firstResults.contains("signal1-connect"))
            #expect(firstResults.contains("connect-signal2"))

            results.withoutSync { $0.removeAll() }

            // Cancel one signal
            controller1.nosync_off()

            // Second emit
            emitter.nosync_emit(event: .connect, data: testData)
            let secondResults = results.withoutSync { $0 }
            #expect(secondResults.count == 3) // once listeners should not fire again, signal1 should not fire
            #expect(secondResults.contains("all-on-connect"))
            #expect(secondResults.contains("connect-on"))
            #expect(secondResults.contains("connect-signal2"))
            #expect(!secondResults.contains("all-once-connect"))
            #expect(!secondResults.contains("connect-once"))
            #expect(!secondResults.contains("signal1-connect"))
        }
    }
}
