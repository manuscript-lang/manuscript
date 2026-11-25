# Padding is one native that builds the result in one block

Verified (2026-11-25): `report` spent 2,225 M instructions on 1 M lines, 12% of them in `pad_start`/`pad_end`, written in `.ms` as `padding_for(...) + self`: two scalar counts, a `repeat` (the exact-size fast path was missing for one-byte padding), a `view().clone()`, and a `concat`. `msrt_string_pad_start`/`pad_end` count the text once, size the filler, and write filler and text into one block (inline when the result is at most 15 bytes): `report` 2,225 M to 1,674 M (-25%), output identical.

The fault rule is unchanged: a filler past the string limit, or a total past it, posts "string: limit exceeded" before any allocation (`text-padding.ms`). Multi-byte padding is cut on a scalar boundary by walking the pattern's first `scalars % pattern_scalars` scalars once.

Apply when: a stdlib string method is a chain of `.ms` calls that each allocate (`repeat`, `clone`, `+`); count allocations per call in callgrind before adding a cache or a new fast path.
