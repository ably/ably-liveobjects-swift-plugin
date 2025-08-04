import Foundation

/// Represents an execution of a test case method.
///
/// This is the equivalent of what ably-cocoa's tests call `Test` (but this name is already taken here by Swift Testing).
struct TestCaseExecution: ~Copyable {
    var id = UUID()
    var description: String

    init(description: String) {
        NSLog("CREATE TestCaseExecution \(id): \(description)")
        self.description = description
    }

    consuming func execute<T, E>(_ testAction: () async throws(E) -> T) async throws(E) -> T {
        do {
            NSLog("BEGIN TestCaseExecution \(id): \(description)")
            let returnValue = try await testAction()
            NSLog("FINISH TestCaseExecution \(id): success")
            return returnValue
        } catch {
            NSLog("FINISH TestCaseExecution \(id): error \(error)")
            throw error
        }
    }
}
