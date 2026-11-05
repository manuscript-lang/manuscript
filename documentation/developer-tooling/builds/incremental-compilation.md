+++
title = "Build caches"
weight = 4
+++

# Build caches

Rebuild changed source without hiding stale inputs from review; save this as `cached.ms`.

<!-- manuscript-example: {"mode":"run","stdout":"Ready to review\n","filename":"cached.ms"} -->
```manuscript {filename="cached.ms"}
export fn main() Int:
    print("Ready to review")
    return 0
```

```sh
ms build cached.ms -o cached
./cached
```

```text
Built cached
Ready to review
```

- Repeat `build` to reuse unchanged output; `run`, `test` and `profile` rebuild instead.
- Manuscript is in alpha; syntax, APIs and cache behavior may change.

## Force a fresh build

```sh
MS_CACHE=off ms build cached.ms -o cached
```

```text
Built cached
```

- POSIX shell syntax; use this when investigating newly shadowed imports.
- Cache validation uses listed inputs; a new shadowing file alone may not invalidate it.

<span id="what-a-build-reuses"></span>
<span id="cache-locations"></span>

Next: [cache identity and invalidation](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-build/src/cache.rs) and [local tool setup](../how-it-works.md#build-tools-and-local-setup).
