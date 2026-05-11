# UserDefinedTypeSupport

An experiment to convince ourselves that, if we later wanted to, we could
layer support for user-specified object shapes (the Swift analogue of
ably-js's `channel.object.get<MyChannelObject>()`) on top of the unshaped
path-based API, without breaking it.

If you only want to read one file, read
[`Example/Shape.swift`](./Example/Shape.swift) — it shows what the API would
ideally look like to a user. Everything else here is the supporting
machinery that makes those call sites compile.

Nothing here is intended to ship as part of the initial GA — the plan is to
ship the unshaped API first. This directory only exists to prove the
additive-layering claim. See the discussion in
[`PATH-BASED-API.md`](../../../../PATH-BASED-API.md) for the design notes
that informed it.

It's also not yet a complete proof. Specifically:

- The hand-written stand-in in `Example/GeneratedCode.swift` still has
  unfilled pieces — the `PathObjectKnownEntry.init?(key:pathObject:)`
  implementations are `fatalError("TODO")`, and there are flagged TODOs in
  the surrounding code about how the conversions would actually need to
  work.
- No real codegen has been demonstrated. There is no `@LiveMapShape` macro
  yet; the "generated" code is written by hand to prove the call-site
  shape compiles. The hardest parts of the codegen story (interpreting the
  user's property types so that, say, a `ShapedLiveMap<TopLevelMap>`
  property turns into a `case` carrying `any
  ShapedLiveMapPathObject<TopLevelMap>`) are noted in TODOs but not
  actually exercised.

So we haven't yet convinced ourselves that the additive-layering claim
holds. This directory shows that the *shape* of the public API is
expressible in Swift and that example call sites compile, but the
codegen-and-runtime-glue layer underneath remains unproven.

## Files

- **[`PublicShapedTypes.swift`](./PublicShapedTypes.swift)** — the public
  protocol family and types: `LiveMapShape`, `LiveMapKey`,
  `LiveMapInitialEntry`, `LiveMapPathObjectKnownEntry`, `ShapedLiveMap`,
  `TypedPrimitivePathObject`, `ShapedLiveMapPathObjectEntry`,
  `ShapedLiveMapPathObject`, plus the `RealtimeObject.get(withShape:)`
  entry point.
- **[`KeyPathConvenience.swift`](./KeyPathConvenience.swift)** — the
  `extension ShapedLiveMapPathObject` adding `keyAt:` variants of `get`,
  `set` and `remove`, so call sites can write `\.topLevelCounter` instead of
  `MyChannelObject.LiveMapKeys.topLevelCounter`.
- **[`Example/Shape.swift`](./Example/Shape.swift)** — the user-written side
  of the example: a `MyChannelObject` struct that would be annotated with a
  hypothetical `@LiveMapShape` macro, plus two example functions
  demonstrating use of the API (one using explicit `LiveMapKeys`
  references, the other using the key-path convenience).
- **[`Example/GeneratedCode.swift`](./Example/GeneratedCode.swift)** — the
  hand-written stand-in for what a `@LiveMapShape` macro would generate from
  `MyChannelObject`: the `LiveMapShape` conformance and the three
  associated-type enums (`LiveMapKeys`, `InitialEntry`,
  `PathObjectKnownEntry`).
