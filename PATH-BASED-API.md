# Notes on the path-based API in Swift

- Have not updated the docstrings
- Unlike in my previous go on this, I am just going to use e.g. `PathObject` directly where the spec does, but make it not be generic, i.e. their `AnyFoo` is my `Foo`
- Where things in the JS API appear to be O(1) things that don't throw and have no side-effects, I am making them properties

- `compact()`:
    - for `LiveMapPathObject` returns `[String: CompactedValue]?`
    - for `LiveCounterPathObject` returns `Double?`

- Have assumed that where the docstring in JS doesn't mention the method throwing, it doesn't throw (e.g. `LiveMapPathObjectCollectionMethods.{entries, keys}`)

## In progress

- `LiveMapOperations.set` now takes a `Value` (i.e. instead of the previous `LiveMapValue`, which I think we need to revisit) — I think that `Value` existed before but we chose not to add, need to look again. but I think that `Value` is being used just for the type system in TS now

- Where have the APIs for getting events out of e.g. a `LiveMap` gone? seems like we no longer have the same-meaning `LiveObject` and it doesn't have the `Update` parameter

## Not done

- The `AsyncIterableIterator` versions of the subscribe methods; I know how they'll look

## Questions

## To do at end

- check all of the `throws`
- check all the `*Base` types are `Sendable`, ditto any new structs
