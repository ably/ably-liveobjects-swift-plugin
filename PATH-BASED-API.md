# Notes on the path-based API in Swift

- Have not updated the docstrings
- Unlike in my previous go on this, I am just going to use e.g. `PathObject` directly where the spec does, but make it not be generic, i.e. their `AnyFoo` is my `Foo`. Ditto `Instance` (their `AnyInstance` is my `Instance`). This is to avoid things like `any AnyInstance` which would look weird, and also because "AnyFoo" already has a meaning in Swift
- Where things in the JS API appear to be O(1) things that don't throw and have no side-effects, I am making them properties
- `compact()`:
  - for `LiveMapPathObject`, `LiveMapInstance`: returns `CompactedValue.ObjectReference?`
  - for `LiveCounterPathObject`, `LiveCounterInstance`: returns `Double?`
  - for `PathObject` returns `CompactedValue?`
- Have assumed that where the docstring in JS doesn't mention the method throwing, it doesn't throw (e.g. `LiveMapPathObjectCollectionMethods.{entries, keys}`)
- `CompactedValue` is represented by a JSON-like type whose collection cases have class instances as their associated data, to allow cycles (see https://github.com/ably/ably-js/pull/2122/files)
  - also do we need an API to allow people to try and convert this to a `JSONValue`?
- I've introduced the `Primitive` type which was omitted from Swift in the first API, because it's now used in multiple places (i.e. there are `value` getters that return one). And for consistency I've updated `Value` to use it, even though it adds a layer of indirection.

## Not done

- The `AsyncIterableIterator` versions of the subscribe methods; I know how they'll look (we already had one similar)
- The public `ObjectMessage` type that JS has added; it's a lot of code but nothing too interesting

## Questions

- What is the right thing to do for `AnyPathObjectCollectionMethods`? Note that they all take generic parameters that let you specialise that specific call. We don't have an equivalent to that so currently it just collapses to the same as `LiveMapPathObject`, but the problem is that it's not going to work well if we also have a `LiveList` that also has `entries`. We need some other way of communicating "this is the type I want to treat it as".
  - For now I'm going to not have this `AnyPathObjectCollectionMethods`, all of which have a specific behaviour _if_ you resolve to a `LiveMap`, and will instead just have a `asLiveMap` property which gives you a `LiveMapPathObject`, which behaves the same way
  - And then, for consistency, I also just won't have `PathObject` conforming to `AnyOperations`; you have to figure out which type you want, call the e.g. `asLiveCounter` / `asLiveMap` and then call your methods; it's overall a smaller API surface and I think easier to reason about
  - TODO: Find out from Andrii and Mike whether there are any times that you'd actually need to treat a `PathObject` homogeneously
  - TODO: What is the purpose of the `PathObject.get`; do we need it, is there any time that you'd want to use paths without the resolved thing being a map?
  - I'm going to do the same for `Instance` too; won't have `AnyInstanceCollectionMethods` and `AnyOperations` and will instead just have a `asLiveMap` / `asLiveCounter`
  - (An alternative option for just handling the return type option would be to have an `Entries` enum that collects the different collections' `entries` return values)

## The `Instance` API

- Given that `Instance` (their `AnyInstance`) doesn't conform to it, I have made `LiveMapInstanceCollectionMethods` not behave as if the instance might not be a map. Concretely, this means that none of the "if not a map" documented behaviours apply, and `size` does not return an optional. (Ditto `LiveCounterInstance.value` returns non-optional)
  - I think that once you have an `Instance` you should be sure about its type. I don't see why we're trying to provide a homogeneous type for instances

## Other questions

- It remains unclear whether things like `value` etc can throw given channel state conditions (so all of my `Instance` things are non-throwing at the moment, but maybe they should retain the same `throws` as they currently have?)
- Why do we have an `Instance` type for a primitive value? An "instance" suggests an "instance of an object", and in this context I'd read that as meaning "instance of a LiveObject".

## To do at end

- check all of the `throws`
- check all the `*Base` types are `Sendable`, ditto any new structs
