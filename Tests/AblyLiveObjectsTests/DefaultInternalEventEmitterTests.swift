// NOTE: This file is adapted from the WIP ably-swift (taken from there at commit 98996f1).

@testable import AblyLiveObjects
import Foundation
import Testing

@MainActor
struct DefaultInternalEventEmitterTests {
    // Test event types for testing
    enum TestEvent: String, Equatable, CaseIterable {
        case connect
        case disconnect
        case message
    }

    struct TestData: Equatable {
        let value: String
    }

    // MARK: - RTE3 Tests (on method)

    @Test
    func onListenerForAllEvents() async throws {
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>()
        var receivedEvents: [(TestEvent, TestData)] = []

        // RTE3: Register listener for all events
        emitter.on { event, data in
            receivedEvents.append((event, data))
        }

        let testData = TestData(value: "test")
        emitter.emit(event: .connect, data: testData)
        emitter.emit(event: .disconnect, data: testData)

        #expect(receivedEvents.count == 2)
        #expect(receivedEvents[0].0 == .connect)
        #expect(receivedEvents[1].0 == .disconnect)
    }

    @Test
    func onListenerForSpecificEvent() async throws {
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>()
        var receivedData: [TestData] = []

        // RTE3: Register listener for specific event
        emitter.on(.connect) { data in
            receivedData.append(data)
        }

        let testData = TestData(value: "test")
        emitter.emit(event: .connect, data: testData)
        emitter.emit(event: .disconnect, data: testData) // Should not trigger listener

        #expect(receivedData.count == 1)
        #expect(receivedData[0].value == "test")
    }

    @Test
    func onListenerWithSignal() async throws {
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>()
        let controller = SubscriptionController()
        var receivedEvents: [(TestEvent, TestData)] = []

        // RTE3: Register listener with signal
        emitter.on(signalledBy: controller.signal) { event, data in
            receivedEvents.append((event, data))
        }

        let testData = TestData(value: "test")
        emitter.emit(event: .connect, data: testData)

        // RTE5: Cancel subscription
        controller.off()

        emitter.emit(event: .disconnect, data: testData) // Should not trigger

        #expect(receivedEvents.count == 1)
        #expect(receivedEvents[0].0 == .connect)
    }

    @Test
    func onListenerMultipleRegistrations() async throws {
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>()
        var callCount = 0

        let listener: MainActorEventListener<TestEvent, TestData> = { _, _ in
            callCount += 1
        }

        // RTE3: If on is called more than once with same listener, it's added multiple times
        emitter.on(listener)
        emitter.on(listener)

        let testData = TestData(value: "test")
        emitter.emit(event: .connect, data: testData)

        #expect(callCount == 2) // Listener should be called twice
    }

    @Test
    func onListenerForSpecificEventWithSignal() async throws {
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>()
        let controller = SubscriptionController()
        var receivedData: [TestData] = []

        // RTE3: Register listener for specific event with signal
        emitter.on(.connect, signalledBy: controller.signal) { data in
            receivedData.append(data)
        }

        let testData = TestData(value: "test")
        emitter.emit(event: .connect, data: testData)
        emitter.emit(event: .disconnect, data: testData) // Should not trigger listener

        #expect(receivedData.count == 1)
        #expect(receivedData[0].value == "test")

        // RTE5: Cancel subscription
        controller.off()

        emitter.emit(event: .connect, data: testData) // Should not trigger after off()
        #expect(receivedData.count == 1) // Should not increment
    }

    // MARK: - RTE4 Tests (once method)

    @Test
    func onceListenerForAllEvents() async throws {
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>()
        var receivedEvents: [(TestEvent, TestData)] = []

        // RTE4: Register one-time listener
        emitter.once { event, data in
            receivedEvents.append((event, data))
        }

        let testData = TestData(value: "test")
        emitter.emit(event: .connect, data: testData)
        emitter.emit(event: .disconnect, data: testData) // Should not trigger

        #expect(receivedEvents.count == 1)
        #expect(receivedEvents[0].0 == .connect)
    }

    @Test
    func onceListenerForSpecificEvent() async throws {
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>()
        var receivedData: [TestData] = []

        // RTE4: Register one-time listener for specific event
        emitter.once(.connect) { data in
            receivedData.append(data)
        }

        let testData = TestData(value: "test")
        emitter.emit(event: .connect, data: testData)
        emitter.emit(event: .connect, data: testData) // Should not trigger again

        #expect(receivedData.count == 1)
        #expect(receivedData[0].value == "test")
    }

    @Test
    func onceListenerMultipleRegistrations() async throws {
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>()
        var callCount = 0

        let listener: MainActorEventListener<TestEvent, TestData> = { _, _ in
            callCount += 1
        }

        // RTE4: If once is called multiple times with same listener, each registration is invoked once
        emitter.once(listener)
        emitter.once(listener)

        let testData = TestData(value: "test")
        emitter.emit(event: .connect, data: testData)

        #expect(callCount == 2) // Both registrations should be called once

        emitter.emit(event: .disconnect, data: testData) // Should not trigger any more
        #expect(callCount == 2) // Count should remain the same
    }

    @Test
    func onceListenerWithSignal() async throws {
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>()
        let controller = SubscriptionController()
        var receivedEvents: [(TestEvent, TestData)] = []

        // RTE4: Register one-time listener with signal
        emitter.once(signalledBy: controller.signal) { event, data in
            receivedEvents.append((event, data))
        }

        // RTE5: Cancel subscription before it fires
        controller.off()

        let testData = TestData(value: "test")
        emitter.emit(event: .connect, data: testData) // Should not trigger due to off()

        #expect(receivedEvents.isEmpty)
    }

    @Test
    func onceListenerForSpecificEventWithSignal() async throws {
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>()
        let controller = SubscriptionController()
        var receivedData: [TestData] = []

        // RTE4: Register one-time listener for specific event with signal
        emitter.once(.connect, signalledBy: controller.signal) { data in
            receivedData.append(data)
        }

        // RTE5: Cancel subscription before it fires
        controller.off()

        let testData = TestData(value: "test")
        emitter.emit(event: .connect, data: testData) // Should not trigger due to off()

        #expect(receivedData.isEmpty)
    }

    // MARK: - RTE6 Tests (emit method)

    @Test
    func emitCallsAllRegisteredListeners() async throws {
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>()
        var allEventCallCount = 0
        var namedEventCallCount = 0

        emitter.on { _, _ in allEventCallCount += 1 }
        emitter.on(.connect) { _ in namedEventCallCount += 1 }

        let testData = TestData(value: "test")
        emitter.emit(event: .connect, data: testData)

        #expect(allEventCallCount == 1)
        #expect(namedEventCallCount == 1)
    }

    // MARK: - RTE6a Tests (listener set stability during emit)

    @Test
    func emitListenerSetStability() async throws {
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>()
        var callOrder: [String] = []

        emitter.on { _, _ in
            callOrder.append("first")
            // Add another listener during emit - should not be called in this emit
            emitter.on { _, _ in
                callOrder.append("added-during-emit")
            }
        }

        emitter.on { _, _ in
            callOrder.append("second")
        }

        let testData = TestData(value: "test")
        emitter.emit(event: .connect, data: testData)

        // RTE6a: Only original listeners should be called
        #expect(callOrder == ["first", "second"])

        // Emit again - now the added listener should be called
        callOrder.removeAll()
        emitter.emit(event: .disconnect, data: testData)
        #expect(callOrder == ["first", "second", "added-during-emit"])
    }

    @Test
    func emitListenerRemovalDuringEmit() async throws {
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>()
        let controller = SubscriptionController()
        var callOrder: [String] = []

        emitter.on { _, _ in
            callOrder.append("first")
            // Remove this listener during emit - but it should still complete per RTE6a
            controller.off()
        }

        emitter.on(signalledBy: controller.signal) { _, _ in
            callOrder.append("second")
        }

        let testData = TestData(value: "test")
        emitter.emit(event: .connect, data: testData)

        // RTE6a: Both listeners should be called despite removal during emit
        #expect(callOrder == ["first", "second"])

        // Emit again - now only first listener should be called
        callOrder.removeAll()
        emitter.emit(event: .disconnect, data: testData)
        #expect(callOrder == ["first"])
    }

    // MARK: - RTE5 Tests (off method)

    @Test
    func offRemovesAllListeners() async throws {
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>()
        var allEventCallCount = 0
        var connectCallCount = 0
        var disconnectCallCount = 0

        // Register various listeners
        emitter.on { _, _ in allEventCallCount += 1 }
        emitter.on(.connect) { _ in connectCallCount += 1 }
        emitter.on(.disconnect) { _ in disconnectCallCount += 1 }

        let testData = TestData(value: "test")

        // Verify listeners work before off()
        emitter.emit(event: .connect, data: testData)
        #expect(allEventCallCount == 1)
        #expect(connectCallCount == 1)
        #expect(disconnectCallCount == 0)

        // RTE5: Remove all listeners
        emitter.off()

        // Reset counters and emit - no listeners should be called
        allEventCallCount = 0
        connectCallCount = 0
        disconnectCallCount = 0

        emitter.emit(event: .connect, data: testData)
        emitter.emit(event: .disconnect, data: testData)

        #expect(allEventCallCount == 0)
        #expect(connectCallCount == 0)
        #expect(disconnectCallCount == 0)
    }

    @Test
    func offForSpecificEventRemovesOnlyThatEvent() async throws {
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>()
        var allEventCallCount = 0
        var connectCallCount = 0
        var disconnectCallCount = 0

        // Register various listeners
        emitter.on { _, _ in allEventCallCount += 1 }
        emitter.on(.connect) { _ in connectCallCount += 1 }
        emitter.on(.disconnect) { _ in disconnectCallCount += 1 }

        let testData = TestData(value: "test")

        // Verify listeners work before off()
        emitter.emit(event: .connect, data: testData)
        #expect(allEventCallCount == 1)
        #expect(connectCallCount == 1)
        #expect(disconnectCallCount == 0)

        // RTE5: Remove only connect listeners
        emitter.off(.connect)

        // Reset counters and emit - only connect listeners should be removed
        allEventCallCount = 0
        connectCallCount = 0
        disconnectCallCount = 0

        emitter.emit(event: .connect, data: testData)
        #expect(allEventCallCount == 1) // All-event listener should still work
        #expect(connectCallCount == 0) // Connect listener should be removed
        #expect(disconnectCallCount == 0)

        emitter.emit(event: .disconnect, data: testData)
        #expect(allEventCallCount == 2) // All-event listener should still work
        #expect(connectCallCount == 0)
        #expect(disconnectCallCount == 1) // Disconnect listener should still work
    }

    // MARK: - RTE5 - SubscriptionController Tests

    @Test
    func subscriptionControllerOff() async throws {
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>()
        let controller = SubscriptionController()
        var callCount = 0

        emitter.on(signalledBy: controller.signal) { _, _ in
            callCount += 1
        }

        let testData = TestData(value: "test")
        emitter.emit(event: .connect, data: testData)
        #expect(callCount == 1)

        controller.off()
        emitter.emit(event: .disconnect, data: testData)
        #expect(callCount == 1) // Should not increment
    }

    @Test
    func unsubscribeFromWithinListener() async throws {
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>()
        let controller = SubscriptionController()
        var callCount = 0

        // Test unsubscribing from within listener callback
        emitter.on(signalledBy: controller.signal) { _, _ in
            callCount += 1
            controller.off() // Unsubscribe from within callback
        }

        let testData = TestData(value: "test")
        emitter.emit(event: .connect, data: testData)
        #expect(callCount == 1)

        // Should not be called again
        emitter.emit(event: .disconnect, data: testData)
        #expect(callCount == 1)
    }

    @Test
    func subscriptionControllerOffDoesNotAffectFutureSubscriptions() async throws {
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>()
        let controller = SubscriptionController()
        var firstCallCount = 0
        var secondCallCount = 0

        // First subscription
        emitter.on(signalledBy: controller.signal) { _, _ in
            firstCallCount += 1
        }

        let testData = TestData(value: "test")
        emitter.emit(event: .connect, data: testData)
        #expect(firstCallCount == 1)

        // Cancel first subscription
        controller.off()

        // Add another subscription with the same signal - should work
        emitter.on(signalledBy: controller.signal) { _, _ in
            secondCallCount += 1
        }

        emitter.emit(event: .disconnect, data: testData)
        #expect(firstCallCount == 1) // Should not increment
        #expect(secondCallCount == 1) // Should work despite previous off() call
    }

    @Test
    func subscriptionContinuesAfterControllerDeallocation() async throws {
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>()
        var callCount = 0

        // Create subscription with controller that will be deallocated
        weak var weakController: SubscriptionController?
        do {
            let controller = SubscriptionController()
            weakController = controller
            emitter.on(signalledBy: controller.signal) { _, _ in
                callCount += 1
            }

            // Verify subscription works initially
            let testData = TestData(value: "test")
            emitter.emit(event: .connect, data: testData)
            #expect(callCount == 1)

            // Controller will be deallocated when leaving this scope
        }
        // Confirm the controller has been deallocated
        precondition(weakController == nil)

        // Emit another value now that the controller has been deallocated
        let testData = TestData(value: "test2")
        emitter.emit(event: .disconnect, data: testData)

        // The subscription should still work because listener registration is independent
        // of controller lifetime - only calling off() should remove it
        #expect(callCount == 2)
    }

    // MARK: - Mixed Scenarios Tests

    @Test
    func mixedOnAndOnceListeners() async throws {
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>()
        var onCallCount = 0
        var onceCallCount = 0

        emitter.on { _, _ in onCallCount += 1 }
        emitter.once { _, _ in onceCallCount += 1 }

        let testData = TestData(value: "test")
        emitter.emit(event: .connect, data: testData)
        #expect(onCallCount == 1)
        #expect(onceCallCount == 1)

        emitter.emit(event: .disconnect, data: testData)
        #expect(onCallCount == 2) // Should increment
        #expect(onceCallCount == 1) // Should not increment
    }

    @Test
    func mixedAllEventAndNamedEventListeners() async throws {
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>()
        var allEventCallCount = 0
        var connectCallCount = 0
        var disconnectCallCount = 0

        emitter.on { _, _ in allEventCallCount += 1 }
        emitter.on(.connect) { _ in connectCallCount += 1 }
        emitter.on(.disconnect) { _ in disconnectCallCount += 1 }

        let testData = TestData(value: "test")

        emitter.emit(event: .connect, data: testData)
        #expect(allEventCallCount == 1)
        #expect(connectCallCount == 1)
        #expect(disconnectCallCount == 0)

        emitter.emit(event: .disconnect, data: testData)
        #expect(allEventCallCount == 2)
        #expect(connectCallCount == 1)
        #expect(disconnectCallCount == 1)

        emitter.emit(event: .message, data: testData)
        #expect(allEventCallCount == 3)
        #expect(connectCallCount == 1)
        #expect(disconnectCallCount == 1)
    }

    @Test
    func complexScenario() async throws {
        let emitter = DefaultInternalEventEmitter<TestEvent, TestData>()
        let controller1 = SubscriptionController()
        let controller2 = SubscriptionController()
        var results: [String] = []

        // Mix of on/once, all-event/named-event, with/without signals
        emitter.on { event, _ in results.append("all-on-\(event)") }
        emitter.once { event, _ in results.append("all-once-\(event)") }
        emitter.on(.connect) { _ in results.append("connect-on") }
        emitter.once(.connect) { _ in results.append("connect-once") }
        emitter.on(signalledBy: controller1.signal) { event, _ in results.append("signal1-\(event)") }
        emitter.on(.connect, signalledBy: controller2.signal) { _ in results.append("connect-signal2") }

        let testData = TestData(value: "test")

        // First emit
        emitter.emit(event: .connect, data: testData)
        #expect(results.count == 6)
        #expect(results.contains("all-on-connect"))
        #expect(results.contains("all-once-connect"))
        #expect(results.contains("connect-on"))
        #expect(results.contains("connect-once"))
        #expect(results.contains("signal1-connect"))
        #expect(results.contains("connect-signal2"))

        results.removeAll()

        // Cancel one signal
        controller1.off()

        // Second emit
        emitter.emit(event: .connect, data: testData)
        #expect(results.count == 3) // once listeners should not fire again, signal1 should not fire
        #expect(results.contains("all-on-connect"))
        #expect(results.contains("connect-on"))
        #expect(results.contains("connect-signal2"))
        #expect(!results.contains("all-once-connect"))
        #expect(!results.contains("connect-once"))
        #expect(!results.contains("signal1-connect"))
    }
}
