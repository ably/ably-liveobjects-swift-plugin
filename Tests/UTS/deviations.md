# UTS Deviations (Path-Based LiveObjects)

Records where the Swift translations diverge from the UTS pseudocode. Per the `uts-to-swift`
workflow, this file is only for **SDK non-compliance** and **language / mock-capability gaps** — not
for harness-driving differences (those are explained in code comments).

## Adapted Tests (typed-language gaps)

These spec cases pass an intentionally wrong-typed argument and expect a runtime error. Swift's typed
`create(...)` signatures and the `LiveMapValue` union reject those inputs **at compile time**, so the
runtime error assertion cannot be written. The test bodies keep the spec point and exercise the valid
construction only, with an inline `// DEVIATION` note. (Same resolution as ably-java.)

| Spec point | Spec says | SDK behaviour | Affected test |
|---|---|---|---|
| `RTLCV3c` | `LiveCounter.create("not_a_number")` succeeds (no validation at create) | `create(initialCount: Double)` rejects a `String` at compile time | `ValueTypesTests.test_RTLCV3c_no_validation_at_creation_time` |
| `RTLCV4a` | evaluating `LiveCounter.create("not_a_number")` throws `40003` | non-number rejected at compile time | `ValueTypesTests.test_RTLCV4a_consumption_validates_count_type` |
| `RTLMV4a` | `LiveMap.create(null)` → evaluation throws `40003` | `create(entries: [String: LiveMapValue])` rejects `null` at compile time | `ValueTypesTests.test_RTLMV4a_consumption_validates_entries_type` |
| `RTLMV4b` | non-String key `{ 123: "value" }` → `40003` | Swift dictionary keys are typed `String`; non-String key not constructible | `ValueTypesTests.test_RTLMV4b_consumption_validates_key_types` |
| `RTLMV4c` | unsupported value (a function) → `40013` | `LiveMapValue` only constructs from supported types; unsupported value rejected at compile time | `ValueTypesTests.test_RTLMV4c_consumption_validates_value_types` |

## Adapted Assertions (wire format)

| Spec point | Spec says | SDK / wire behaviour | Affected test |
|---|---|---|---|
| `RTLCV4g5` | assert `operation.counterCreate.count == 42` on the generated message | the local `CounterCreate` (`derivedFrom`) is stripped from the wire message; the count is verified via the `counterCreateWithObjectId.initialValue` JSON string instead (same as ably-js) | `ValueTypesTests.test_RTLCV4g5_consumption_retains_local_CounterCreate` |
| `RTLMV4j5` | assert `operation.mapCreate.semantics/entries` on the generated message | local `MapCreate` stripped from wire; verified via `mapCreateWithObjectId.initialValue` JSON string | `ValueTypesTests.test_RTLMV4j5_consumption_retains_local_MapCreate` |
| `RTLMV4d` | assert on generated `mapCreate.entries[k].data.<field>` | verified via the `mapCreateWithObjectId.initialValue` JSON string (the retained `mapCreate` is stripped from wire) | `ValueTypesTests.test_RTLMV4d_*` |
| `RTO24b2c` | a subscription listener that **throws** must not affect other listeners | Swift's `PathObjectSubscriptionCallback` is `@Sendable (…) -> Void` (non-throwing), so a throwing listener isn't expressible; the test keeps a no-op first listener and asserts the second still fires | `PathObjectSubscribeTests.test_RTO24b2c_listener_exception_does_not_affect_others` |
| `RTINS12d` / `RTINS14d` / `RTINS15d` / `RTINS16c` | calling a wrong-type operation on an `Instance` (e.g. `set` on a counter, `increment`/`subscribe` on a map/primitive) throws 92007 | Swift models `Instance` as an enum; `set`/`increment`/`decrement`/`subscribe` exist only on the relevant payload protocol, so a wrong-type call can't be written at all — the runtime 92007 path is compile-time-unreachable | `InstanceTests.test_RTINS12d_*` / `test_RTINS14d_*` / `test_RTINS16c_*` (empty, documented) |
| `RTINS10` | `Instance.compact()` recursive compaction | only `compactJson()` is exposed publicly; asserted on the JSON form | `InstanceTests.test_RTINS10_compact_recursively_compacts` |
| `RTINS4d` / `RTINS9c` | `value()`/`size()` return null for the wrong wrapped type | Swift exposes `value`/`size` only on the relevant payload; "returns null" is represented as "not that payload type" | `InstanceTests.test_RTINS4_*` / `test_RTINS9_*` |
| `RTO15` | `channel.object.publish([...])` sends an `OBJECT` PM and returns a `PublishResult` | `publish` / `PublishResult` are internal RealtimeObject members, not on the public `RealtimeObject` protocol (which exposes only `get()` / `on(...)`); the publish path is covered indirectly via the path-object mutation tests (RTO20) | `RealtimeObjectTests.test_RTO15_publish_sends_object_protocol_message` (empty, documented) |

## Mock Infrastructure Limitations

_None yet._
