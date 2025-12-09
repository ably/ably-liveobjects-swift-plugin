# Notes on the path-based API in Swift

- Have not updated the docstrings
- Unlike in my previous go on this, I am just going to use e.g. `PathObject` directly where the spec does, but make it not be generic, i.e. their `AnyFoo` is my `Foo`. Ditto `Instance` (their `AnyInstance` is my `Instance`)
- Where things in the JS API appear to be O(1) things that don't throw and have no side-effects, I am making them properties

- `compact()`:
    - for `LiveMapPathObject` returns `[String: JSONValue]?`
    - for `LiveCounterPathObject` returns `Double?`
    - for `PathObject` returns `JSONValue?`

- Have assumed that where the docstring in JS doesn't mention the method throwing, it doesn't throw (e.g. `LiveMapPathObjectCollectionMethods.{entries, keys}`)

- I haven't done `CompactedValue` because it seems like in the end what you can get out of it is equivalent to a `JSONValue` — check

## In progress

- `LiveMapOperations.set` now takes a `Value` (i.e. instead of the previous `LiveMapValue`, which I think we need to revisit) — I think that `Value` existed before but we chose not to add, need to look again. but I think that `Value` is being used just for the type system in TS now

- Where have the APIs for getting events out of e.g. a `LiveMap` gone? seems like we no longer have the same-meaning `LiveObject` and it doesn't have the `Update` parameter

## Not done

- The `AsyncIterableIterator` versions of the subscribe methods; I know how they'll look

## Questions

- What is the right thing to do for `AnyPathObjectCollectionMethods`? Note that they all take generic parameters that let you specialise that specific call. We don't have an equivalent to that so currently it just collapses to the same as `LiveMapPathObject`, but the problem is that it's not going to work well if we also have a `LiveList` that also has `entries`. We need some other way of communicating "this is the type I want to treat it as".
    - For now I'm going to not have this `AnyPathObjectCollectionMethods`, all of which have a specific behaviour _if_ you resolve to a `LiveMap`, and will instead just have a `asLiveMap` property which gives you a `LiveMapPathObject`, which behaves the same way
    - And then, for consistency, I also just won't have `PathObject` conforming to `AnyOperations`; you have to figure out which type you want, call the e.g. `asLiveCounter` / `asLiveMap` and then call your methods; it's overall a smaller API surface and I think easier to reason about
    - TODO: Find out from Andrii and Mike whether there are any times that you'd actually need to treat a `PathObject` homogeneously
    - TODO: What is the purpose of the `PathObject.get`; do we need it, is there any time that you'd want to use paths without the resolved thing being a map?

## To do at end

- check all of the `throws`
- check all the `*Base` types are `Sendable`, ditto any new structs
