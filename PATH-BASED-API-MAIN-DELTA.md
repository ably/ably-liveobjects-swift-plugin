# Bringing the proposed Swift path-based API into line with ably-js main

This document records a comparison between the version of the ably-js path-based
API that the Swift port (`Sources/AblyLiveObjects/Public/PublicTypes.swift`) was
based on, and the version currently on ably-js `main`. It enumerates the
changes that affect the Swift public surface, and lists the smaller set of
follow-up changes needed to align it.

## What was compared

- **Basis** — `ably.d.ts` as it existed in ably-js at commit `0bdd674` (which is
  no longer reachable from ably-js `main`, since the integration branch it
  belonged to was rebased). The Swift port copied this file into the repo on
  commit `3a002f4 Copy ably.d.ts from ably-js at 0bdd674` and the proposed
  Swift API has been derived from it ever since. The file is checked in at the
  repo root as `ably.d.ts`.
- **Target** — `liveobjects.d.ts` on ably-js `main` at commit `498d26df`
  (the tip of `origin/main` at the time of writing; the file itself was last
  touched on main by `4235266a Implement LiveObjects REST client`). The
  LiveObjects type definitions have been moved out of `ably.d.ts` into a
  dedicated module since the basis was copied.

## Method

The two files were read end to end and compared section by section, focused on
the symbols that the Swift port currently models (the path-based API,
`Instance`, `CompactedValue`, the `LiveMap` / `LiveCounter` factories and the
`RealtimeObject` entry point).

The following are deliberately out of scope:

- **The REST LiveObjects API** (`RestObject`, `RestObjectOperation*`,
  `RestLiveMap`, `RestLiveCounter`, etc.) — there is no plan to port this to
  Swift imminently.
- `BatchContext` / `BatchOperations` / `batch()` — present in both basis and
  main but deliberately omitted from the Swift port; not a basis→main delta.
- Choices the Swift port made for Swift-idiomatic reasons (e.g. method-vs-property
  for `id`, `path`, `value`, `instance`) — these are orthogonal to the diff.

## Findings

### Changes that affect the Swift public surface today

#### 1. Remove `RealtimeObject.offAll()`

- Basis: `RealtimeObject` had `get`, `on`, `off(event, callback)` and
  `offAll()`.
- Main: `offAll()` was removed (ably-js commit `09ecb55f`). Listeners are
  deregistered either via the `StatusSubscription` returned by `.on()` or via
  `off(event, callback)`.
- Swift today: `PublicTypes.swift` still declares
  `RealtimeObject.offAll()`. Delete it. Swift doesn't currently expose
  `off(event:callback:)` either, but that's fine — `StatusSubscription.off()`
  covers individual unsubscription.

#### 2. Implement implicit channel attach in `RealtimeObject.get()`

- Main: `get()` now *"Implicitly attaches to the channel if not already
  attached"* (ably-js commit `96c39f9d`). This is a behavioural change, not
  just a docstring change — the SDK has to perform the attach.
- Swift today: `RealtimeObject.get()` is a stub (`fatalError("Not
  implemented")`) and the behaviour is not modelled. Tracked separately as
  [AIT-455][3]. Beyond the implementation, the docstring on
  `RealtimeObject.get()` should also be updated to call this out.

#### 3. Split `compact()` into `compact()` + `compactJson()`

This is the substantive change. It is recorded retroactively in [LODR-057][1]
and was implemented in [ably-js#2129][2]. The motivation is that the single
`compact()` from the basis was trying to be both an in-memory, traversable
representation *and* a JSON-serialisable one, and the two goals conflict:

- For cycle handling, an in-memory representation can use shared object
  pointers (cheap, easy to traverse, but not JSON-serialisable); a
  JSON-serialisable representation has to use `{ objectId: string }` references
  (loses type-checker support, but `JSON.stringify`-safe).
- For binary data, in-memory wants to preserve the original `Buffer`/`Data`
  (so callers can tell strings from bytes); JSON-serialisable wants
  base64-encoded strings (consistent with the REST API).

The basis conflated the two: cycles were already shared in memory (so the
result wasn't `JSON.stringify`-safe) but binary was base64-encoded (so the
original type was lost). The split in main resolves this:

- `CompactedValue<T>` (in-memory) — LiveMap → object, LiveCounter → number,
  binary stays as `Buffer | ArrayBuffer`, cycles via shared in-memory
  references. Provides full TypeScript intellisense.
- `CompactedJsonValue<T>` (JSON-serialisable, new) — same shape, but binary →
  base64 string, cycles → a new `ObjectIdReference` (`{ objectId: string }`).
  Consistent with the REST API's compact representation.

Concrete Swift consequences:

- **`CompactedValue` enum needs a `.data(Data)` case.** Today it has
  `.string`, `.number`, `.bool`, `.null`, `.object`, `.array` — modelled on
  the basis where binary was base64-stringified. In main's `CompactedValue`,
  binary must survive as `Data`. Cycle handling, on the other hand, is
  already correct: Swift's `ObjectReference` / `ArrayReference` are `final
  class`es, so the existing type already supports in-memory cycles via shared
  class references, which is exactly the new `CompactedValue` semantics.
- **For the JSON-serialisable form, pick one of two designs.**
  - *Option A: introduce a new `CompactedJsonValue` Swift type.* Unlike
    `CompactedValue`, this one must *not* permit in-memory cycles: object
    and array payloads should be value types (e.g. `[String:
    CompactedJsonValue]` / `[CompactedJsonValue]` directly, rather than
    wrapped in a class), and cycles are represented explicitly via a new
    `ObjectIdReference` value (e.g. `struct ObjectIdReference { let
    objectId: String }`). Binary appears as `.string` (base64-encoded).
    In JS the point of this representation is that it can be fed straight
    to `JSON.stringify`. Swift callers don't get that for free, so we'd
    probably also want a `toJSONValue()` method converting to the existing
    `JSONValue` (a total conversion, since `CompactedJsonValue` has no
    cycles) and/or a convenience that goes directly to `Data`.
  - *Option B: just return `JSONValue` directly from `compactJson()`.*
    Skip introducing a new Swift type entirely. This is arguably closer to
    what JS actually does: `CompactedJsonValue` and `ObjectIdReference` are
    only *type-level* distinctions in TypeScript — at runtime,
    `ObjectIdReference` is just a plain `{ objectId: string }` object,
    indistinguishable from any other JSON object. Callers detect cycles by
    checking for the `objectId` key. Returning `JSONValue` from
    `compactJson()` matches that reality, removes a public type from the
    Swift surface, and subsumes the toJSON-conversion question raised in
    [`PATH-BASED-API.md`](./PATH-BASED-API.md). The cost is that the
    cycle/objectId case is no
    longer pattern-matchable as a distinct enum case — callers inspect the
    object shape, same as JS callers do.

  Option B looks like the right default unless we want the Swift API to
  expose a typed distinction that JS doesn't.
- **Add `compactJson()` to every type that has `compact()`** —
  `PathObject`, `LiveMapPathObject`, `LiveCounterPathObject`, and the
  corresponding `Instance` variants. Return types depend on which option
  above is chosen:
  - Under option A: `CompactedJsonValue?` for the general/LiveMap cases,
    `Double?` for the counter cases. Note that JS's return type for the
    LiveMap case is `CompactedJsonValue<LiveMap<T>> = { ... } |
    ObjectIdReference`, so the top-level result can itself be an
    `ObjectIdReference` — the Swift return type can't be the narrow
    "object form only" analogue used for `compact()` on `LiveMapPathObject`.
  - Under option B: `JSONValue?` for general/LiveMap cases (callers detect
    cycles via the `objectId` key), `Double?` for counters.

### Changes that don't affect Swift today

These affect the `ObjectMessage` / `ObjectOperation` / `ObjectData` internals,
which Swift has deliberately stubbed out (see the `ObjectMessage` placeholder
in `PublicTypes.swift`). They'll need to be reflected when `ObjectMessage` is
fleshed out, but no action is needed now:

- **New `MAP_CLEAR` operation action** and `MapClear` payload type.
- **New `UNKNOWN` cases** in both `ObjectOperationAction` and
  `ObjectsMapSemantics` (forward-compat for unrecognised server values).
- **`ObjectOperation` gets typed per-action payloads** (`mapCreate`, `mapSet`,
  `mapRemove`, `counterCreate`, `counterInc`, `objectDelete`, `mapClear`).
  Old `mapOp` / `counterOp` / `map` / `counter` are kept but `@deprecated`.
- **`ObjectData` gets typed leaf fields** (`boolean`, `bytes`, `number`,
  `string`, `json`); the old `value: Primitive` is `@deprecated`.

### Things that look like changes but aren't

- **`LiveMap.create` / `LiveCounter.create` static factories.** The Swift
  port already implements these (commits `c58f455` and `b33178d`) and they
  are aligned with main. The naming wasn't a Swift invention: at basis time
  it was already the documented public API even though the `.d.ts` hadn't
  yet caught up. Specifically:
  - The basis `ably.d.ts` (at `0bdd674`) didn't expose any factories on
    `LiveMap` / `LiveCounter` — they were empty branded interfaces.
  - The ably-js *runtime* at the same commit already had the factory
    methods, just on differently-named classes:
    `LiveMapValueType.create()` and `LiveCounterValueType.create(initialCount
    = 0)` in `src/plugins/objects/{livemapvaluetype,livecountervaluetype}.ts`.
  - The migration guide added in `b083173e` (the direct child of the basis,
    less than 10 hours later) already documents the public API as
    `LiveMap.create()` / `LiveCounter.create()` from line 145 onwards.
  - On main, the `.d.ts` now exposes those factories with the documented
    names via `class LiveMap { static create<T>(...) }` /
    `class LiveCounter { static create(initialCount?) }`,
    declaration-merged with the branded interface of the same name.

  One small follow-up worth checking: Swift's `LiveCounter.create(initialCount:
  Double = 0)` should produce the same wire payload as JS's
  `LiveCounter.create()` with no argument, i.e. the `COUNTER_CREATE` payload
  should match what main sends when `initialCount` is `undefined`.
- **`id` as a property** (`readonly id: string | undefined` on `InstanceBase`
  and `BatchContextBase` in main, vs `id(): string | undefined` method in the
  basis). Swift already uses `var id: String? { get }` — accidentally correct.
- **`path` / `value` / `instance` as properties vs methods.** Swift turned
  these into properties as a deliberate idiomatic choice; that's orthogonal to
  the basis→main delta (both JS versions use methods).
- **`Subscription` / `StatusSubscription` / structured subscribe callback
  (`{ object, message }`).** The basis already had the new structured callback
  shape, so no change is needed.
- **`subscribeIterator`.** Identical in both; Swift has commented it out as a
  known TODO — no action required relative to this diff.
- **`BatchContext` / `BatchOperations` / `batch()` method.** Present in both
  basis and main; Swift deliberately doesn't expose it. No basis→main delta.
- **Stale `LiveObject` lifecycle types in Swift**
  (`OnLiveObjectLifecycleEventResponse`, `LiveObjectLifecycleEventCallback`):
  unused leftovers from a pre-`9d67c25` state. Can be deleted, but unrelated
  to this diff.

## TL;DR action list for the Swift port

1. Remove `RealtimeObject.offAll()`.
2. Implement implicit channel attach in `RealtimeObject.get()` ([AIT-455][3]),
   and update its docstring.
3. Add a `.data(Data)` case to `CompactedValue` so it can hold in-memory
   binary.
4. Decide between option A (introduce a `CompactedJsonValue` type with
   `.string` for base64 binary and an `ObjectIdReference` value for cycles)
   and option B (just return the existing `JSONValue` from `compactJson()`,
   matching JS's runtime behaviour). Option B is the suggested default.
5. Add `compactJson()` to every type that currently has `compact()`, with the
   return type implied by the choice in (4).
6. (Deferred, when `ObjectMessage` is filled in) model `MAP_CLEAR`, `UNKNOWN`,
   the new typed `ObjectOperation` payloads, and the new typed `ObjectData`
   leaves.

[1]: https://ably.atlassian.net/wiki/spaces/LOB/pages/4710694927/LODR-057+SDK+API+for+JSON+Serialized+and+memory-traversable+compact+object+representations
[2]: https://github.com/ably/ably-js/pull/2129
[3]: https://ably.atlassian.net/browse/AIT-455
