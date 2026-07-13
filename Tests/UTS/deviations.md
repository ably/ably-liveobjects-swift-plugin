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
| `RTLO4b4c1` | noop `COUNTER_INC` (a `counterInc` with no `number`) must not trigger the listener | `WireCounterInc.number` is a non-optional `NSNumber`, so an empty `counterInc: {}` isn't constructible; the test asserts two real increments produce exactly two updates | `LiveObjectSubscribeTests.test_RTLO4b4c1_noop_update_does_not_trigger_listener` |
| `RTO4b2a` | the reset LiveMapUpdate for root must have `objectMessage == null` | the internal `DefaultLiveMapUpdate` carries no `objectMessage` field, so this cannot be asserted; the removed-entry update itself is asserted instead | `ObjectsPoolTests.test_RTO4b_attached_without_has_objects_clears_pool_and_syncs` |
| `RTO7`/`RTO8a` | an OBJECT message received while INITIALIZED is buffered | this SDK only buffers while SYNCING (it relies on the invariant that OBJECT messages only arrive after ATTACHED → SYNCING); in INITIALIZED it applies immediately. The test asserts the SDK's actual behaviour (object created, nothing buffered) | `ObjectsPoolTests.test_RTO7_RTO8_object_message_in_initialized_state` |
| `RTO9a2b` | an unsupported-action OBJECT message is discarded and no object is created (pool keeps only root) | this SDK creates the zero-value object (RTO9a2a2) *before* the action check (RTO9a2b), so the object exists but the operation is not applied. The test asserts the operation had no effect (counter stays zero-valued) rather than the pool size | `ObjectsPoolTests.test_RTO9a2b_unsupported_action_is_discarded` |

## Skeleton API added to host these tests

Two files exercised functionality that had **no symbol at all** in this branch (not even a trapping
skeleton). Rather than defer them, the API shapes were added as `notImplemented()` skeletons (like
the rest of the path-based target), so the tests bind to real symbols, compile, and trap at runtime
until the behaviour is implemented:

- **`parent_references.md`** (`RTLO3f` / `RTLO4f` / `RTLO4g` / `RTLO4h`, `RTO5c10`): added the
  ``ParentReferencing`` protocol (`parentReferences`, `addParentReference`, `removeParentReference`,
  `getFullPaths`) with `notImplemented()` defaults, conformed by `InternalDefaultLiveCounter` /
  `InternalDefaultLiveMap`. → `ParentReferencesTests`.
- **`public_object_message.md`** (`PAOM3` / `PAOOP3`): added `ObjectMessage.fromObjectMessage(_:channelName:)`
  and `ObjectOperation.fromObjectOperation(_:)` as `notImplemented()` skeletons (the spec's
  `PublicObjectMessage` / `PublicObjectOperation` map to the SDK's `ObjectMessage` / `ObjectOperation`;
  the `channel` object is represented by its name). → `PublicObjectMessageTests`.

A minimal `testsOnly_objectsSyncState` accessor and an `ObjectsPool.testsOnly_setEntry(_:forObjectID:)`
seed helper were also added to `Sources` to let the internal-engine tests assert sync state and
pre-seed the pool.

## Mock Infrastructure Limitations

_None yet._
