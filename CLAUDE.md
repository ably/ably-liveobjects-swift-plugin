# CLAUDE.md

## Build

```sh
swift build
```

## Test

When verifying changes, always run the unit tests first:

```sh
swift run BuildTool test-library --platform macOS --only-unit-tests
```

This is fast (a few seconds) and excludes integration tests. Only run the full test suite if explicitly asked.

## Lint

```sh
swift run BuildTool lint
```

Use `--fix` to auto-fix where possible.
