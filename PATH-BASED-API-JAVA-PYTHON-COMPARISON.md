# Comparison with the Java / Python path-based API proposal

This document compares the Swift path-based API proposal in this repo to the
parallel Java / Python proposal authored by Evgenii in
[ably/ably-java#1190][1]. The comparison was carried out against the state
of the PR at commit [`be13cdc`][2] (branch `draft-new-lo-api`, file
`liveobjects/PATH_BASED_API_JAVA_PYTHON.md`). It is concerned only with the
*conversion* decisions — the ways the cross-SDK path-based model has been
adapted for Java and Python — and how those compare to what we have done in
Swift.

## Provenance

Evgenii wrote his document *after* the Swift design discussion in which the
type-erased-`PathObject` + `asLiveMap` / `asLiveCounter` pattern was proposed;
the `as*` cast pattern in the Java / Python doc is presumably directly inspired by that
discussion. However, Evgenii hadn't seen the exact Swift API surface in
detail when writing his proposal, so the places where the two designs diverge
are not necessarily intentional statements of preference — some of them may
simply reflect parallel evolution from the same starting point.

## How the Java / Python document is structured

Evgenii's document doesn't separate the cross-SDK design decisions inherited
from ably-js (deferred resolution, single root object per channel, atomic
deep creation via nested `*.create()`, path-based subscriptions with depth,
no object ID exposure outside the `Instance` API) from the Java/Python-specific
conversion decisions that are new in the doc. The rest of this document picks
out the latter and compares them to what we have in Swift.

## Conversion decisions

### Type-erased `PathObject` plus `as*` casts

**Both:** the base `PathObject` doesn't try to expose the union of all
possible types; callers reach the type-specific surface via
`asLiveMap` / `asLiveCounter` / etc. This is the central shared design choice.

### How primitives are represented

**Java / Python:** four distinct primitive path-object types
(`StringPathObject`, `NumberPathObject`, `BooleanPathObject`,
`BinaryPathObject`), each exposing its own natively-typed `value()` returning
`String` / `Double` / `Boolean` / `byte[]` respectively. There is no
language-level enum for "any primitive". The type emerges from *which*
`as*Primitive()` cast you called.

**Swift:** no per-primitive path-object type at all — primitives are read via
`var value: Primitive?` on `PathObject` directly, where `Primitive` is a
single Swift enum. The rationale for not porting `PrimitivePathObject` from
the ably-js basis is recorded in [`PATH-BASED-API.md`](./PATH-BASED-API.md)
(the basis type carried
only `value()` and `compact()`, both of which already sit naturally on
`PathObject`). The decision to expose a single `Primitive`-returning getter
rather than per-primitive-case path-object types is a design choice — Swift
could perfectly well have followed evgenii's per-case split, since nothing
about Swift forces the collapsed shape. The argument for keeping it
collapsed is simply that primitive path objects don't have any operations of
their own that distinguish a string from a number from a binary blob — they
all just expose `value()` and `compact()` — so introducing four separate
types per primitive case mostly buys typed-by-construction return values, at
the cost of multiplying the API surface. If we did decide to introduce a
per-primitive variant later, the natural shape would be a *single*
`PrimitivePathObject` whose `value()` returns the `Primitive` enum, rather
than four per-case types.

### Whether `value()` and `instance()` are on the base `PathObject`

**Java / Python:** they are not. The base `PathObject` exposes only `path()`,
`compact()`, the seven `as*` cast methods, and `subscribe()`. To read any
value or grab any instance, you must first cast.

**Swift:** the base `PathObject` exposes `var value: Primitive?` and
`var instance: Instance?` directly, in addition to `asLiveMap` /
`asLiveCounter`. A caller can take a primitive-typed read off any
`PathObject` without going through a cast.

### Which path-object types carry `instance()`

**Java / Python:** only `LiveMapPathObject` has `instance()`. Neither
`LiveCounterPathObject` nor the primitive path objects expose it. (This is
probably an oversight rather than a deliberate choice — there's no positive
rationale given for it in the doc, the use case described under "Design
Decision #6" applies equally to counters, and ably-js exposes `instance()` on
both `LiveCounterPathObject` and `LiveMapPathObject`.)

**Swift:** `instance` is exposed on `PathObject` (returning the type-erased
`Instance?`), on `LiveMapPathObject` (returning `LiveMapInstance?`), and on
`LiveCounterPathObject` (returning `LiveCounterInstance?`).

### Failure mode when a path doesn't resolve to the expected type

**Java:** every `value()` plus `LiveMapPathObject.instance()` is declared
`throws AblyException` and returns a non-nullable type (`String`, `Double`,
`LiveMap`, etc.). The `as*` cast itself is non-throwing, so the type-mismatch
failure is deferred to the leaf accessor and surfaces as an exception. The
doc does not explicitly explain this; it falls out of Design Decision #2
("fails fast if the type doesn't match") combined with the absence of any
`Optional<T>` returns on these accessors.

**Python:** mixed. `LiveMapPathObject.instance()` is typed as
`Optional['LiveMap']`, so it can legitimately return `None` rather than
raising. The primitive `value()` methods (e.g. `def value(self) -> str:`)
return plain non-`Optional` types, so for those a type mismatch presumably
has to surface by raising. This isn't called out in the doc and reads more
like an inconsistency between the Java and Python sketches than a deliberate
split.

**Swift:** the corresponding accessors return optionals
(`var value: Primitive?`, `var instance: LiveMapInstance?`, etc.) and don't
throw on type mismatch. This matches the ably-js semantics of returning
`undefined` for the same condition.

### Mutation methods

**Java / Python:** `set` / `remove` / `increment` / `decrement` all take a
`MessageOptions` parameter, allowing callers to set an explicit message id
and `extras` on the published operation.

**Swift:** no `MessageOptions` analogue is currently exposed on the
path-based mutation methods. (Not exposed on the ably-js path-based API
either.)

### Creating primitive values for mutations

**Java / Python:** primitives are wrapped via `Primitive.create("...")` /
`Primitive.create(10)` etc. when passing them to `set()`.

**Swift:** primitive `Value` cases (`.string`, `.number`, `.bool`, `.data`,
`.jsonArray`, `.jsonObject`) plus the `ExpressibleBy*Literal` conformances
let callers write the literal directly inside the `[String: Value]` argument
to `set` / `createMap`.

### `compact()` return type

**Java / Python:** exposes a single `compact()` returning plain `JsonValue`
(the existing JSON-shaped type in the SDK). What evgenii calls `compact()`
here is structurally the JSON-serialisable form — equivalent to ably-js
main's `compactJson()`, with binary encoded as base64 strings and cycles
represented via `{ objectId }` references.

There is no in-memory analogue. The ably-js split between an in-memory
`compact()` (cycles as shared in-memory references, binary preserved as raw
bytes, type information unambiguous) and a JSON-serialisable `compactJson()`
isn't engaged with in the doc. evgenii's doc post-dates the split landing
in ably-js main (the split is commit `3887fe9` on 2025-12-18; evgenii's
proposal is commit `be13cdc` on 2026-02-11), so this isn't a case of him
working from a pre-split snapshot — but the doc doesn't acknowledge or
discuss the trade-off, for unknown reasons. The consequence is that callers
can't obtain an unambiguous in-memory representation, can't tell a raw
binary value apart from a string that happens to look base64-shaped, and
can't traverse cycles by following in-memory pointers.

**Swift:** currently has `CompactedValue` as a class-backed enum supporting
in-memory cycles — closer in spirit to ably-js main's in-memory `compact()`.
The Swift proposal *does* predate the ably-js split: it's based on `ably.d.ts`
at `0bdd674` (2025-12-09), nine days before the split landed, so the single
`compact()` it inherits is just the pre-split shape. Adding the
JSON-serialisable form alongside it is captured as a follow-up in
[`PATH-BASED-API-MAIN-DELTA.md`](./PATH-BASED-API-MAIN-DELTA.md), where two
shapes for the *JSON-form* return type are weighed: option A (introduce a
dedicated `CompactedJsonValue` type) and option B (have `compactJson()`
simply return the existing `JSONValue`). Both options presuppose keeping
the in-memory `compact()`; the A/B choice is only about the return shape of
the JSON-form method. So Swift's planned end state has both halves of the
ably-js split; the Java / Python proposal has only the JSON half.

### `LiveList`

**Java / Python:** `LiveListPathObject` is included in the type system
already (`asLiveList`, `LiveListPathObject.get(index)`, `size()`), forward-
looking for when LiveList lands.

**Swift:** no `LiveList` type is included yet. (Not in ably-js main either.)

[1]: https://github.com/ably/ably-java/pull/1190
[2]: https://github.com/ably/ably-java/pull/1190/commits/be13cdce9db6b70ea646e56fbba4821ee194f887
